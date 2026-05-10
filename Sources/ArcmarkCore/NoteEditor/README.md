# Note Editor — bundled assets

This directory is copied verbatim into `Arcmark.app/Contents/Resources/NoteEditor/`
and served by `NoteServer` over a token-authenticated loopback HTTP listener.

## Layout

- `index.html` — minimal two-tab UI (Edit / Preview).
- `editor.css` — hand-written styles, no framework.
- `editor.js` — load/save logic against `/api/notes/<uuid>`.
- `vendor/marked.min.js` — markdown parser, fetched from npm.
- `vendor/purify.min.js` — HTML sanitizer for the preview pane.

## Vendored library versions

| File              | Package    | Version | Source                                                              |
| ----------------- | ---------- | ------- | ------------------------------------------------------------------- |
| `marked.min.js`   | marked     | 13.0.3  | https://cdn.jsdelivr.net/npm/marked@13.0.3/marked.min.js            |
| `purify.min.js`   | dompurify  | 3.1.6   | https://cdn.jsdelivr.net/npm/dompurify@3.1.6/dist/purify.min.js     |

To update, replace the file in `vendor/` with a newer minified build from npm
and update the table above. There is no build step — the file is shipped as-is.
