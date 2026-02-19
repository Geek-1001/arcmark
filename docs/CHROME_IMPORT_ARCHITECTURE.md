# Chrome Bookmarks HTML Import Architecture

This document describes how Chrome exports bookmarks, the Netscape Bookmark HTML format, and how Arcmark parses and imports them.

## Overview

Chrome (and all Chromium-based browsers) can export bookmarks as an HTML file via the Bookmark Manager. Unlike Arc, which stores bookmarks in a JSON file at a known path, Chrome has no stable file-system path that can be read directly — the user must manually export. Arcmark provides a file picker for the user to select the exported HTML file, then parses it into an Arcmark workspace.

## The Netscape Bookmark File Format

### Background

The Netscape Bookmark File format dates back to the 1990s Netscape Navigator browser. It became the de facto standard for bookmark interchange between browsers. Chrome, Firefox, Safari, Edge, Brave, and virtually all browsers support exporting and importing this format.

The format is **not valid XML or XHTML**. It uses a loose, non-standard HTML dialect with unclosed tags and non-standard elements. This is why the parser uses line-by-line regex scanning rather than an XML/HTML parser.

### Specification Reference

There is no official W3C specification. The format is documented through reverse engineering and community documentation:
- Microsoft's original documentation: [Netscape Bookmark File Format](https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa753582(v=vs.85))
- The `NETSCAPE-Bookmark-file-1` DOCTYPE identifier is the universal marker

### File Structure

```html
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an automatically generated file.
     It will be read and overwritten.
     DO NOT EDIT! -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 ADD_DATE="..." LAST_MODIFIED="..." PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
    <DL><p>
        <DT><A HREF="https://example.com" ADD_DATE="1234567890" ICON="data:image/...">Example</A>
        <DT><H3 ADD_DATE="..." LAST_MODIFIED="...">Subfolder</H3>
        <DL><p>
            <DT><A HREF="https://nested.com" ADD_DATE="1234567890">Nested Link</A>
        </DL><p>
    </DL><p>
    <DT><H3 ADD_DATE="..." LAST_MODIFIED="...">Other bookmarks</H3>
    <DL><p>
        <DT><A HREF="https://other.com" ADD_DATE="1234567890">Other Link</A>
    </DL><p>
</DL><p>
```

### Key Elements

| Element | Meaning | Example |
|---------|---------|---------|
| `<!DOCTYPE NETSCAPE-Bookmark-file-1>` | File format identifier | Always first line |
| `<DL>` | Definition List — opens a group of items | Wraps folder contents |
| `</DL>` | Closes a definition list | Ends folder contents |
| `<DT>` | Definition Term — prefix for each item | Before every link or folder |
| `<H3>` | Folder header | `<DT><H3>Folder Name</H3>` |
| `<A HREF="...">` | Bookmark link | `<DT><A HREF="url">Title</A>` |
| `<p>` | Decorative — has no semantic meaning | Ignored by parser |

### Common Attributes on Elements

**On `<H3>` (folder headers):**
- `ADD_DATE` — Unix timestamp when folder was created
- `LAST_MODIFIED` — Unix timestamp of last modification
- `PERSONAL_TOOLBAR_FOLDER="true"` — marks the Bookmarks bar folder

**On `<A>` (links):**
- `HREF` — the bookmark URL
- `ADD_DATE` — Unix timestamp when bookmark was created
- `ICON` — base64-encoded favicon (data URI), ignored by our parser
- `ICON_URI` — URL to favicon (Firefox), ignored by our parser

### Chrome's Top-Level Folder Structure

Chrome always exports with these top-level folders:

| Folder Name | Chrome UI Location | `PERSONAL_TOOLBAR_FOLDER` |
|-------------|-------------------|---------------------------|
| `Bookmarks bar` | Chrome's bookmarks bar | `true` |
| `Other bookmarks` | "Other Bookmarks" section | not set |
| `Mobile bookmarks` | Synced mobile bookmarks | not set |

These are structural containers, not user-created folders. The importer **flattens** them — their children are merged into the root level of the Arcmark workspace.

## How to Export from Chrome

1. Open Chrome
2. Click the three-dot menu → **Bookmarks and lists** → **Bookmark manager**
3. In the Bookmark Manager, click the three-dot menu (top-right) → **Export bookmarks**
4. Save the HTML file

This produces a file typically named `bookmarks_MM_DD_YY.html`.

## Import Algorithm

### Phase 1: Validation

1. Check the file exists on disk
2. Read as UTF-8 string
3. Validate the content contains `NETSCAPE-Bookmark-file-1`, `<DL>`, or `<dl>` to confirm it's a bookmark file
4. If validation fails, return `.invalidHTML` error

### Phase 2: Line-by-Line Parsing

The parser uses four regex patterns matched against each line:

```
Folder:  <DT><H3[^>]*>(.*?)</H3>         → captures folder name
Link:    <DT><A\s+HREF="([^"]*)"[^>]*>(.*?)</A>  → captures URL and title
Open:    <DL>                              → begins folder contents
Close:   </DL>                             → ends folder contents
```

All patterns use `.caseInsensitive` matching to handle variations.

### Phase 3: Stack-Based Nesting

The parser maintains two parallel stacks:

```
stack: [[Node]]        — each level is the array of nodes being built
folderNameStack: [String]  — folder names awaiting their closing </DL>
```

And a boolean flag:

```
pendingFolder: Bool    — true when a <H3> was just seen (next <DL> belongs to it)
```

#### State Machine

```
Initial state:
  stack = [[]]              (one empty root level)
  folderNameStack = []
  pendingFolder = false

On <DT><H3>Name</H3>:
  Push "Name" onto folderNameStack
  Set pendingFolder = true

On <DT><A HREF="url">Title</A>:
  Validate URL (skip if empty, javascript:, chrome://, or malformed)
  Decode HTML entities in title
  Append Link node to stack.last

On <DL> (when pendingFolder == true):
  Push new empty [] onto stack      (start collecting folder's children)
  Set pendingFolder = false

On <DL> (when pendingFolder == false):
  Ignore                            (structural/root <DL>)

On </DL> (when stack.count > 1):
  Pop children from stack
  Pop folderName from folderNameStack
  If this is a top-level Chrome folder (stack.count == 1 after pop):
    Flatten: append children directly to stack.last
  Else:
    Create Folder node with children, append to stack.last
```

#### Visual Example

Given this HTML:
```html
<DL>
  <DT><H3>Bookmarks bar</H3>
  <DL>
    <DT><A HREF="https://a.com">A</A>
    <DT><H3>Dev</H3>
    <DL>
      <DT><A HREF="https://b.com">B</A>
    </DL>
  </DL>
</DL>
```

Parser trace:
```
Line: <DL>                    → structural, ignore (pendingFolder=false)
Line: <H3>Bookmarks bar</H3> → folderNameStack=["Bookmarks bar"], pendingFolder=true
Line: <DL>                    → pendingFolder=true, push [], stack=[[], []]
Line: <A HREF=a.com>A</A>    → append Link(A) to stack[1]
Line: <H3>Dev</H3>           → folderNameStack=["Bookmarks bar","Dev"], pendingFolder=true
Line: <DL>                    → push [], stack=[[], [Link(A)], []]
Line: <A HREF=b.com>B</A>    → append Link(B) to stack[2]
Line: </DL>                   → pop children=[Link(B)], name="Dev"
                                stack.count=2 (not top-level) → create Folder("Dev")
                                stack=[[], [Link(A), Folder(Dev)]]
Line: </DL>                   → pop children=[Link(A), Folder(Dev)], name="Bookmarks bar"
                                stack.count=1 (top-level!) → FLATTEN
                                stack=[[Link(A), Folder(Dev)]]
Line: </DL>                   → stack.count=1, no folderNameStack items → skip

Result: [Link(A), Folder(Dev, [Link(B)])]
```

### Phase 4: Top-Level Folder Flattening

The following folder names are recognized as Chrome's structural containers and flattened:

```swift
let topLevelFolderNames: Set<String> = [
    "Bookmarks bar",
    "Other bookmarks",
    "Mobile bookmarks",
    "Bookmarks Bar"       // alternate capitalization
]
```

Flattening means: when a `</DL>` closes one of these folders and the stack depth would return to the root level (`stack.count == 1` after pop), the folder's children are appended directly to the root rather than being wrapped in a Folder node.

This ensures the user doesn't see Chrome's internal folder structure in Arcmark. A user with bookmarks in both "Bookmarks bar" and "Other bookmarks" gets all of them at the root level.

### Phase 5: Apply to Arcmark

1. **Create workspace** named "Chrome Bookmarks" with `.ember` color:
   ```swift
   _ = appModel.createWorkspace(name: "Chrome Bookmarks", colorId: .ember)
   ```

2. **Add nodes recursively** using the same `addNodeToWorkspace` helper used by Arc import:
   ```swift
   for node in result.workspace.nodes {
       addNodeToWorkspace(node, parentId: nil, appModel: appModel)
   }
   ```

3. **Stay on Settings**: Unlike Arc import (which restores the previously selected workspace), Chrome import does not call `selectWorkspace`. The new workspace is internally selected by `createWorkspace`; when the user navigates away from Settings, they see the imported workspace.

## Data Mapping

| Chrome HTML Element | Arcmark Concept | Notes |
|---------------------|-----------------|-------|
| `<H3>` folder header | Folder node | Name extracted from inner text |
| `<A HREF>` link | Link node | URL from HREF attribute, title from inner text |
| `<DL>...</DL>` block | Folder children | Nesting depth preserved |
| Bookmarks bar folder | (flattened) | Children merged into root |
| Other bookmarks folder | (flattened) | Children merged into root |
| Mobile bookmarks folder | (flattened) | Children merged into root |
| `ADD_DATE` attribute | (ignored) | Not imported |
| `ICON` attribute | (ignored) | Favicons fetched fresh by FaviconService |
| `LAST_MODIFIED` attribute | (ignored) | Not imported |

## HTML Entity Decoding

Bookmark titles and folder names may contain HTML entities. The parser decodes these five common entities:

| Entity | Character | Example |
|--------|-----------|---------|
| `&amp;` | `&` | `Tom &amp; Jerry` → `Tom & Jerry` |
| `&lt;` | `<` | `a &lt; b` → `a < b` |
| `&gt;` | `>` | `a &gt; b` → `a > b` |
| `&quot;` | `"` | `&quot;hello&quot;` → `"hello"` |
| `&#39;` | `'` | `it&#39;s` → `it's` |

Chrome typically only uses `&amp;` and `&#39;` in practice, but the others are included for completeness since they're part of the HTML standard mandatory character references.

## URL Validation

Links are skipped if any of these conditions are true:

| Condition | Reason |
|-----------|--------|
| URL string is empty | No valid URL |
| Starts with `javascript:` | Bookmarklets, not navigable URLs |
| Starts with `chrome://` | Chrome-internal pages, not accessible from other browsers |
| `URL(string:)` returns `nil` | Malformed URL that Foundation can't parse |

## Why Not XMLParser or HTML Parsing Libraries?

The Netscape Bookmark format has several properties that make XML/HTML parsers a poor choice:

1. **Not valid XML**: The `<p>` tags are unclosed, `<DT>` tags are unclosed, and there's no proper root element
2. **Not valid HTML5**: The DOCTYPE is non-standard (`NETSCAPE-Bookmark-file-1`)
3. **No need for DOM**: We only need four token types (folder, link, DL open, DL close) — a full DOM is unnecessary overhead
4. **Predictable line structure**: Chrome always outputs one element per line with consistent formatting
5. **Zero dependencies**: Regex scanning uses Foundation's `NSRegularExpression`, no third-party libraries needed

The line-by-line regex approach is simple, fast, and robust for this specific format.

## Example: Complete Flow

### Input: Chrome Bookmarks HTML
```html
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
    <DL><p>
        <DT><A HREF="https://github.com" ADD_DATE="1700000000">GitHub</A>
        <DT><H3>Development</H3>
        <DL><p>
            <DT><A HREF="https://stackoverflow.com" ADD_DATE="1700000001">Stack Overflow</A>
            <DT><A HREF="javascript:void(0)">Some Bookmarklet</A>
        </DL><p>
    </DL><p>
    <DT><H3>Other bookmarks</H3>
    <DL><p>
        <DT><A HREF="https://example.com" ADD_DATE="1700000002">Example &amp; More</A>
    </DL><p>
</DL><p>
```

### Output: Arcmark Structure
```
Workspace: "Chrome Bookmarks" (color: ember)
├── Link: "GitHub" (https://github.com)
├── Folder: "Development"
│   └── Link: "Stack Overflow" (https://stackoverflow.com)
└── Link: "Example & More" (https://example.com)
```

### What Happened
1. **"Bookmarks bar"** folder was flattened — its children (GitHub link, Development folder) went to root
2. **"Other bookmarks"** folder was flattened — its child (Example link) went to root
3. **"Some Bookmarklet"** with `javascript:` URL was skipped
4. **`&amp;`** in "Example &amp; More" was decoded to `&`
5. All `ADD_DATE` attributes were ignored

## Differences from Arc Import

| Aspect | Arc Import | Chrome Import |
|--------|-----------|---------------|
| Source | Fixed path (`~/Library/.../StorableSidebar.json`) | User-selected HTML file |
| Format | JSON | Netscape Bookmark HTML |
| Parser | JSONDecoder + Codable models | Line-by-line regex scanner |
| Workspaces | Multiple (one per Arc space) | Single ("Chrome Bookmarks") |
| Top-level folders | N/A (Arc spaces are workspaces) | Flattened into root |
| File picker | No (reads from known path) | Yes (NSOpenPanel, .html filter) |
| Post-import | Restores previous workspace | Selects new workspace, stays on Settings |
| Color assignment | Cyclic (ember, ruby, coral, ...) | Always `.ember` |

## Edge Cases Handled

### 1. Empty Bookmarks File
If the file contains valid Netscape headers but no `<DT>` entries, returns `.noBookmarksFound`.

### 2. Empty Link Titles
Links with empty inner text (e.g., `<DT><A HREF="url"></A>`) get the title "Untitled".

### 3. Nested Top-Level Folders
Only the immediate children of Chrome's structural folders are flattened. If "Bookmarks bar" contains a user folder called "My Stuff", that folder is preserved as-is — only "Bookmarks bar" itself is unwrapped.

### 4. Deep Nesting
Folder nesting of arbitrary depth is fully preserved. The stack-based parser naturally handles this.

### 5. Mixed Content
Folders and links at the same level are preserved in file order. A sequence of link-folder-link produces exactly that order in the output.

### 6. Non-Chrome Browsers
Since all Chromium browsers (Brave, Edge, Vivaldi, Opera) and Firefox export the same Netscape format, the importer works for any of them. The "Chrome" branding in the UI is for clarity, but the parser is format-agnostic.

### 7. Case Variations
All regex patterns use `.caseInsensitive` to handle `<DL>` vs `<dl>`, `<DT>` vs `<dt>`, etc. Some browsers output lowercase HTML.

## Favicon Handling

Favicons are NOT extracted from the HTML file's `ICON` or `ICON_URI` attributes. Instead:

1. Links are created with `faviconPath: nil`
2. When displayed in the UI, `NodeCollectionViewItem` automatically requests favicons from `FaviconService`
3. `FaviconService` fetches fresh favicons asynchronously from each site
4. Favicons are cached in `~/Library/Application Support/Arcmark/Icons/`

Rationale: Chrome's exported `ICON` attributes contain base64-encoded data URIs that would need to be decoded and saved to disk. Fetching fresh favicons is simpler, produces consistent results with the rest of the app, and avoids storing potentially stale icons.

## Error Handling

| Error | When | User-Facing Message |
|-------|------|---------------------|
| `.fileNotFound` | File doesn't exist at the provided URL | "The selected file could not be found." |
| `.invalidHTML` | File lacks `NETSCAPE-Bookmark-file-1`, `<DL>`, or `<dl>` | "The selected file is not a valid Chrome bookmarks HTML file." |
| `.noBookmarksFound` | Valid file structure but no links or folders parsed | "No bookmarks were found in the file." |
| `.parsingFailed(detail)` | Unexpected error during regex compilation or parsing | "Failed to parse Chrome bookmarks: [detail]" |

## Concurrency Model

- The `importFromChrome` method is `async` and returns a `Result` type
- `Task.yield()` is called first to allow the UI to update (show loading spinner)
- `Task.detached` offloads the CPU-intensive parsing to a background thread
- The caller (`handleChromeImport` in `SettingsContentViewController`) runs on `@MainActor`
- A concurrent import guard prevents both Arc and Chrome import from running simultaneously

## Testing

### Test Helper: HTML Generation

Tests use a `createBookmarksHTML(body:)` helper that wraps content in the standard Netscape header:

```swift
func createBookmarksHTML(body: String) -> String {
    return """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
    \(body)
    </DL><p>
    """
}
```

### Test Cases (14 total)

| Test | What It Verifies |
|------|-----------------|
| Basic link parsing | URL and title extracted correctly from `<A>` |
| Folder with nested links | `<H3>` + `<DL>` creates Folder with children |
| Deep nesting (3+ levels) | Stack handles arbitrary depth |
| Top-level folders flattened | "Bookmarks bar" and "Other bookmarks" unwrapped |
| Empty bookmarks file | Returns `.noBookmarksFound` |
| Invalid/non-HTML file | Returns `.invalidHTML` |
| HTML entities decoded | `&amp;`, `&#39;`, etc. in titles |
| Order preserved | Links appear in file order |
| Empty title | Falls back to "Untitled" |
| Workspace properties | Name is "Chrome Bookmarks", colorId is `.ember` |
| File not found | Returns `.fileNotFound` |
| Invalid URLs skipped | `javascript:`, `chrome://`, empty URLs |
| HTML entities in folder names | Entity decoding applies to `<H3>` content too |
| Mixed content | Folders and links at same level, correct order |

## References

### Source Files
- **ChromeImportService.swift** — Parser and import logic
- **SettingsContentViewController.swift** — UI (file picker, buttons, status display)
- **ChromeImportTests.swift** — Unit tests
- **Models.swift** — `Node`, `Folder`, `Link` data models
- **ArcImportService.swift** — `ImportWorkspace` struct (shared between importers)

### External References
- [Netscape Bookmark File Format (Microsoft)](https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa753582(v=vs.85))
- [Chrome Bookmark Manager](https://support.google.com/chrome/answer/188842) — Google's help article on managing bookmarks
- [Chromium source: bookmark_html_writer.cc](https://source.chromium.org/chromium/chromium/src/+/main:chrome/browser/bookmarks/bookmark_html_writer.cc) — Chrome's actual HTML export implementation

## Appendix: Browser Compatibility

The Netscape Bookmark HTML format is exported by all major browsers. The parser should work with exports from:

| Browser | Export Location | Tested |
|---------|----------------|--------|
| Google Chrome | Bookmark Manager → Export | Yes |
| Brave | Bookmark Manager → Export | Expected (same Chromium base) |
| Microsoft Edge | Favorites → Export | Expected (same Chromium base) |
| Vivaldi | Bookmarks → Export | Expected (same Chromium base) |
| Opera | Bookmarks → Export | Expected (same Chromium base) |
| Firefox | Library → Import/Export → Export HTML | Expected (same format) |
| Safari | File → Export Bookmarks | Expected (same format) |

All Chromium-based browsers use the same `bookmark_html_writer.cc` code to generate the HTML, so their output is identical in structure.

### Troubleshooting Import Issues

If import fails:

1. **"Not a valid Chrome bookmarks HTML file"**: The file may be a different format (JSON, XML, or plain text). Ensure you used Chrome's "Export bookmarks" option, not a third-party tool.

2. **"No bookmarks were found"**: The file is valid HTML but contains no `<DT><A>` links. This can happen if Chrome has no bookmarks at all.

3. **Missing bookmarks after import**: Check if some bookmarks had `javascript:` or `chrome://` URLs — these are intentionally skipped. Bookmarklets (JavaScript snippets saved as bookmarks) are not importable.

4. **Garbled characters in titles**: The parser assumes UTF-8 encoding (which Chrome always uses). If the file was re-saved in a different encoding, titles may not decode correctly.
