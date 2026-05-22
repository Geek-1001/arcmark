---
name: arcmark
description: >
  Organize bookmarks, folders, and markdown notes in the Arcmark macOS app.
  ALWAYS use this skill when the user asks to save a link, create a folder,
  move bookmarks between workspaces, take notes, or otherwise tidy their
  Arcmark sidebar.
last-updated: 2026-05-18
allowed-tools: Bash(./scripts/arcmark.js:*)
---

# Arcmark Agent Skill

Arcmark is a macOS sidebar app for organizing bookmarks and short markdown
notes inside named, color-coded **workspaces**. This skill lets you create
and rearrange that content on the user's behalf — atomically, with no manual
file editing.

## Setup / prerequisites

- **Arcmark must be running.** All commands talk to a local HTTP server inside
  the running app.
- If a command exits with `code: "app_not_running"`, **stop and ask the user
  to launch Arcmark.app** before retrying. Do not loop on retries.
- You do not need network access; everything is on `127.0.0.1`.

## Glossary

- **Workspace** — a named, colored top-level container (e.g. "Reading",
  "Work"). Workspaces hold nodes. The agent can create and rename them, but
  **cannot delete workspaces** — this is a hard rule.
- **Folder** — a named container that can hold links, notes, and other
  folders. Nestable.
- **Link** — a bookmark with a title and a URL. The app fetches favicons
  automatically.
- **Note** — a markdown document with a title and a body. Body content is
  stored as a `.md` file and read/written with `notes:read` and `notes:write`.
- **Node** — any of folder, link, or note. Generic operations like
  `nodes:move` work on all three.

## Common Actions

| User phrasing | Command |
|---|---|
| "Save this here" / "Add this to the workspace I'm in" | `workspaces:current` to get the id, then `links:create --workspace WS_ID --url URL` |
| "Save this link in my Reading workspace" | `links:create --workspace WS_ID --url URL` |
| "Add a folder called Reading" | `folders:create --workspace WS_ID --name "Reading"` |
| "Group these tabs into a Research folder in my Reading workspace" | create folder, then `nodes:move` each link with `--to-parent FOLDER_ID` |
| "Move this link to my Work workspace" | `nodes:move LINK_ID --to-workspace WORK_WS_ID` |
| "Rename this folder to Inbox" | `folders:rename FOLDER_ID --name "Inbox"` |
| "Take a note titled Plan" | `notes:create --workspace WS_ID --title "Plan"` |
| "Write up this meeting in a note" | `notes:create ... --content -` then pipe markdown to stdin |
| "What's in my Reading workspace?" | `tree WS_ID` |
| "Make a new workspace called Research" | `workspaces:create --name "Research"` |
| "Delete this bookmark" | `nodes:delete NODE_ID` (or `links:delete`) |

## Workflow

1. **Find ids first.** Run `arcmark.js state` (or `arcmark.js workspaces:list`
   plus `arcmark.js tree WORKSPACE_ID`) to discover the workspace, folder,
   and node UUIDs you need. Never invent or guess ids.
   - When the user says "this workspace", "the current one", "the one I'm
     in", or "here", resolve it with `arcmark.js workspaces:current`. The
     response is `{ selected, settingsSelected, workspace: { id, name, colorId } | null }`.
     If `selected` is false (e.g. the user is on the Settings screen),
     ask which workspace to use instead of guessing.
2. **Decide on a target.** Pick which workspace and (optionally) parent
   folder a new node should live in. If the user is ambiguous, ask.
3. **Compose atomic mutations.** Run one CLI command per action. Each
   command is a single API call; the running app updates the sidebar
   immediately.
4. **Confirm before destructive bulk work.** Before deleting multiple
   nodes — especially folders containing many children — confirm with the
   user. Deletes are not undoable from the CLI.

## Writing note bodies

Three ways to supply note content, in order of preference for long
documents:

- `--content -` reads the body from stdin. Use this when piping or
  here-docs:

  ```bash
  ./scripts/arcmark.js notes:write NOTE_ID --content - <<'EOF'
  # Heading
  Paragraph with **markdown**.
  EOF
  ```

- `--file path/to/file.md` reads a file from disk.

- `--content "..."` for short snippets that fit on a single command line.

`notes:read NOTE_ID` prints the body to stdout so you can fetch existing
content before editing.

## Moving across workspaces

`nodes:move` is the universal mover. It accepts:

- `--to-workspace ID` — moves to a different workspace. Omit to move within
  the current workspace.
- `--to-parent ID` — drops the node inside that folder. Pass the literal
  `root` to move to the workspace root.
- `--index N` — position within the parent (0-based). Omit to append.

Combinations:

- Same workspace, reorder: `nodes:move ID --to-parent FOLDER_ID --index 0`
- Cross workspace, into a folder: `nodes:move ID --to-workspace WS --to-parent FOLDER_ID`
- Cross workspace, to root: `nodes:move ID --to-workspace WS --to-parent root`

## Rules and limits

- **Never delete a workspace.** There is no command for it; do not try.
  If the user explicitly asks, explain that workspaces must be removed
  manually from the app.
- Workspace **color names**: Blush, Apricot, Butter, Leaf, Mint, Sky,
  Periwinkle, Lavender. Case-insensitive; raw enum cases (ember, ruby,
  coral, tangerine, moss, ocean, indigo, graphite) also work.
- Every command exits non-zero on failure and prints `{ error, code, ... }`
  to stderr. Inspect `code` — `app_not_running`, `workspace_not_found`,
  `parent_not_folder`, `node_not_found` are the common ones.

## Commands Reference

```
state                                  Dump the full AppState JSON.
tree WORKSPACE_ID                      Dump one workspace's tree.

workspaces:list
workspaces:current                       Workspace currently visible in the app.
workspaces:create        --name "X" [--color NAME]
workspaces:rename ID     --name "Y"
workspaces:set-color ID  --color NAME

folders:create   --workspace ID [--parent ID|root] --name "X" [--expanded true|false]
folders:rename   ID  --name "Y"
folders:delete   ID

links:create     --workspace ID [--parent ID|root] --url URL [--title T]
links:rename     ID  --title "Y"
links:set-url    ID  --url URL
links:delete     ID

notes:create     --workspace ID [--parent ID|root] --title T [--content TEXT | --file PATH | --content -]
notes:rename     ID  --title "Y"
notes:read       ID
notes:write      ID  --content TEXT | --file PATH | --content -
notes:delete     ID

nodes:move       ID [--to-workspace ID] [--to-parent ID|root] [--index N]
nodes:delete     ID
```

## Examples

Group two existing links into a new folder inside the Reading workspace:

```bash
# 1. Find the ids.
./scripts/arcmark.js workspaces:list
# -> [{"id":"...reading...","name":"Reading", ...}]

./scripts/arcmark.js tree READING_WS_ID
# Pick out the two link ids from the tree output.

# 2. Create the folder.
FOLDER_ID=$(./scripts/arcmark.js folders:create \
  --workspace READING_WS_ID --name "Research" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

# 3. Move each link into it.
./scripts/arcmark.js nodes:move LINK_ID_1 --to-parent "$FOLDER_ID"
./scripts/arcmark.js nodes:move LINK_ID_2 --to-parent "$FOLDER_ID"
```

Create a note in Reading and fill it with markdown from stdin:

```bash
NOTE_ID=$(./scripts/arcmark.js notes:create \
  --workspace READING_WS_ID --title "Weekly plan" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

./scripts/arcmark.js notes:write "$NOTE_ID" --content - <<'EOF'
# Weekly plan

- Finish the report
- Email the team
EOF
```

Save a link in Work, then move it to a Reading subfolder:

```bash
LINK_ID=$(./scripts/arcmark.js links:create \
  --workspace WORK_WS_ID --url "https://anthropic.com" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

./scripts/arcmark.js nodes:move "$LINK_ID" \
  --to-workspace READING_WS_ID --to-parent RESEARCH_FOLDER_ID
```
