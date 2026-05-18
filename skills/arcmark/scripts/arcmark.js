#!/usr/bin/env node
// arcmark.js — zero-dependency CLI for the Arcmark agent skill.
//
// Talks to the local HTTP server inside the running Arcmark.app via the
// endpoint file written to ~/Library/Application Support/Arcmark/agent-endpoint.json.
// All output is JSON to stdout. Errors print {error,code,...} to stderr and
// exit non-zero.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const ENDPOINT_FILE = path.join(
  os.homedir(),
  'Library',
  'Application Support',
  'Arcmark',
  'agent-endpoint.json'
);

// ---------- Argument parsing ----------

function parseArgs(argv) {
  const positional = [];
  const flags = {};
  let i = 0;
  while (i < argv.length) {
    const arg = argv[i];
    if (arg === '--') {
      positional.push(...argv.slice(i + 1));
      break;
    }
    if (arg.startsWith('--')) {
      const eq = arg.indexOf('=');
      let key, value;
      if (eq >= 0) {
        key = arg.slice(2, eq);
        value = arg.slice(eq + 1);
      } else {
        key = arg.slice(2);
        const next = argv[i + 1];
        if (next === undefined || next.startsWith('--')) {
          value = true;
        } else {
          value = next;
          i++;
        }
      }
      flags[normalizeFlag(key)] = value;
    } else {
      positional.push(arg);
    }
    i++;
  }
  return { positional, flags };
}

function normalizeFlag(name) {
  return name.replace(/_/g, '-').toLowerCase();
}

function getFlag(flags, ...names) {
  for (const name of names) {
    const k = normalizeFlag(name);
    if (Object.prototype.hasOwnProperty.call(flags, k)) {
      return flags[k];
    }
  }
  return undefined;
}

function requireFlag(flags, name) {
  const v = getFlag(flags, name);
  if (v === undefined || v === true) {
    fail('missing_flag', `Missing required --${name}`);
  }
  return v;
}

// ---------- IO helpers ----------

function readEndpoint() {
  let raw;
  try {
    raw = fs.readFileSync(ENDPOINT_FILE, 'utf8');
  } catch (e) {
    fail(
      'app_not_running',
      'Arcmark does not appear to be running. Ask the user to launch Arcmark.app, then retry.',
      { endpointFile: ENDPOINT_FILE }
    );
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    fail('endpoint_corrupt', 'agent-endpoint.json is not valid JSON', { endpointFile: ENDPOINT_FILE });
  }
  if (!parsed || typeof parsed.port !== 'number') {
    fail('endpoint_corrupt', 'agent-endpoint.json missing port', { endpointFile: ENDPOINT_FILE });
  }
  return { host: parsed.host || '127.0.0.1', port: parsed.port };
}

async function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

function printJSON(obj) {
  process.stdout.write(JSON.stringify(obj, null, 2) + '\n');
}

function fail(code, message, extra = {}) {
  const payload = { error: message, code, ...extra };
  process.stderr.write(JSON.stringify(payload, null, 2) + '\n');
  process.exit(1);
}

// ---------- HTTP ----------

async function request(method, route, body) {
  const { host, port } = readEndpoint();
  const url = `http://${host}:${port}${route}`;
  const init = { method, headers: {} };
  if (body !== undefined) {
    init.headers['Content-Type'] = 'application/json';
    init.body = typeof body === 'string' ? body : JSON.stringify(body);
  }
  let res;
  try {
    res = await fetch(url, init);
  } catch (e) {
    fail('http_failed', `Could not reach Arcmark at ${url}: ${e.message}`);
  }
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch (e) {
    fail('bad_response', `Non-JSON response from ${url}`, { status: res.status, body: text });
  }
  if (!res.ok || json.ok === false) {
    fail(json.code || 'http_error', json.error || `HTTP ${res.status}`, {
      status: res.status,
    });
  }
  return json;
}

// ---------- Command handlers ----------

const COMMANDS = {
  'help': cmdHelp,

  'state': cmdState,
  'tree': cmdTree,

  'workspaces:list': cmdWorkspacesList,
  'workspaces:create': cmdWorkspacesCreate,
  'workspaces:rename': cmdWorkspacesRename,
  'workspaces:set-color': cmdWorkspacesSetColor,

  'folders:create': cmdFoldersCreate,
  'folders:rename': cmdFoldersRename,
  'folders:delete': cmdNodesDelete,

  'links:create': cmdLinksCreate,
  'links:rename': cmdLinksRename,
  'links:set-url': cmdLinksSetUrl,
  'links:delete': cmdNodesDelete,

  'notes:create': cmdNotesCreate,
  'notes:rename': cmdNotesRename,
  'notes:read': cmdNotesRead,
  'notes:write': cmdNotesWrite,
  'notes:delete': cmdNodesDelete,

  'nodes:move': cmdNodesMove,
  'nodes:delete': cmdNodesDelete,
};

async function cmdState() {
  const out = await request('GET', '/api/state');
  printJSON(out.state || out);
}

async function cmdTree(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: tree WORKSPACE_ID');
  const out = await request('GET', `/api/workspaces/${id}/tree`);
  printJSON(out.workspace || out);
}

async function cmdWorkspacesList() {
  const out = await request('GET', '/api/workspaces');
  printJSON(out.workspaces || []);
}

async function cmdWorkspacesCreate(args) {
  const name = requireFlag(args.flags, 'name');
  const body = { name };
  const color = getFlag(args.flags, 'color');
  if (color !== undefined && color !== true) body.colorId = color;
  const out = await request('POST', '/api/workspaces', body);
  printJSON({ id: out.id });
}

async function cmdWorkspacesRename(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: workspaces:rename ID --name "Y"');
  const name = requireFlag(args.flags, 'name');
  await request('PATCH', `/api/workspaces/${id}`, { name });
  printJSON({ ok: true });
}

async function cmdWorkspacesSetColor(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: workspaces:set-color ID --color NAME');
  const color = requireFlag(args.flags, 'color');
  await request('PATCH', `/api/workspaces/${id}`, { colorId: color });
  printJSON({ ok: true });
}

async function cmdFoldersCreate(args) {
  const workspaceId = requireFlag(args.flags, 'workspace');
  const name = requireFlag(args.flags, 'name');
  const body = { workspace_id: workspaceId, name };
  const parent = getFlag(args.flags, 'parent');
  if (parent !== undefined && parent !== true && parent !== 'root') {
    body.parent_id = parent;
  }
  const expanded = getFlag(args.flags, 'expanded');
  if (expanded !== undefined) body.expanded = expanded === true || expanded === 'true';
  const out = await request('POST', '/api/folders', body);
  printJSON({ id: out.id });
}

async function cmdFoldersRename(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: folders:rename ID --name "Y"');
  const name = requireFlag(args.flags, 'name');
  await request('PATCH', `/api/folders/${id}`, { name });
  printJSON({ ok: true });
}

async function cmdLinksCreate(args) {
  const workspaceId = requireFlag(args.flags, 'workspace');
  const url = requireFlag(args.flags, 'url');
  const body = { workspace_id: workspaceId, url };
  const parent = getFlag(args.flags, 'parent');
  if (parent !== undefined && parent !== true && parent !== 'root') {
    body.parent_id = parent;
  }
  const title = getFlag(args.flags, 'title');
  if (title !== undefined && title !== true) body.title = title;
  const out = await request('POST', '/api/links', body);
  printJSON({ id: out.id });
}

async function cmdLinksRename(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: links:rename ID --title "Y"');
  const title = requireFlag(args.flags, 'title');
  await request('PATCH', `/api/links/${id}`, { title });
  printJSON({ ok: true });
}

async function cmdLinksSetUrl(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: links:set-url ID --url URL');
  const url = requireFlag(args.flags, 'url');
  await request('PATCH', `/api/links/${id}`, { url });
  printJSON({ ok: true });
}

async function cmdNotesCreate(args) {
  const workspaceId = requireFlag(args.flags, 'workspace');
  const title = requireFlag(args.flags, 'title');
  const body = { workspace_id: workspaceId, title };
  const parent = getFlag(args.flags, 'parent');
  if (parent !== undefined && parent !== true && parent !== 'root') {
    body.parent_id = parent;
  }
  const content = await resolveContent(args.flags);
  if (content !== undefined) body.content = content;
  const out = await request('POST', '/api/notes', body);
  printJSON({ id: out.id });
}

async function cmdNotesRename(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: notes:rename ID --title "Y"');
  const title = requireFlag(args.flags, 'title');
  await request('PATCH', `/api/notes/${id}`, { title });
  printJSON({ ok: true });
}

async function cmdNotesRead(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: notes:read ID');
  const out = await request('GET', `/api/notes/${id}`);
  process.stdout.write(out.content ?? '');
  if (!String(out.content ?? '').endsWith('\n')) {
    process.stdout.write('\n');
  }
}

async function cmdNotesWrite(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: notes:write ID --content "..." | --file PATH | --content -');
  const content = await resolveContent(args.flags);
  if (content === undefined) {
    fail('missing_content', 'Provide --content "..." (or "-" for stdin) or --file PATH');
  }
  await request('PUT', `/api/notes/${id}`, { content });
  printJSON({ ok: true });
}

async function cmdNodesMove(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: nodes:move ID [--to-workspace ID] [--to-parent ID|root] [--index N]');
  const body = {};
  const toWs = getFlag(args.flags, 'to-workspace');
  if (toWs !== undefined && toWs !== true) body.to_workspace_id = toWs;
  const toParent = getFlag(args.flags, 'to-parent');
  if (toParent !== undefined && toParent !== true) {
    body.to_parent_id = toParent === 'root' ? null : toParent;
  }
  const index = getFlag(args.flags, 'index');
  if (index !== undefined && index !== true) {
    const n = parseInt(index, 10);
    if (Number.isNaN(n)) fail('bad_index', '--index must be an integer');
    body.index = n;
  }
  await request('POST', `/api/nodes/${id}/move`, body);
  printJSON({ ok: true });
}

async function cmdNodesDelete(args) {
  const id = args.positional[0];
  if (!id) fail('missing_arg', 'Usage: <type>:delete ID');
  await request('DELETE', `/api/nodes/${id}`);
  printJSON({ ok: true });
}

// ---------- Content resolution (--content / --file / stdin) ----------

async function resolveContent(flags) {
  const file = getFlag(flags, 'file');
  if (file !== undefined && file !== true) {
    if (file === '-') return await readStdin();
    try {
      return fs.readFileSync(file, 'utf8');
    } catch (e) {
      fail('file_unreadable', `Could not read ${file}: ${e.message}`);
    }
  }
  const content = getFlag(flags, 'content');
  if (content === undefined) return undefined;
  if (content === true) fail('missing_content', '--content requires a value (or "-" for stdin)');
  if (content === '-') return await readStdin();
  return content;
}

// ---------- Help ----------

const HELP = `arcmark.js — organize bookmarks, folders, and notes in the Arcmark macOS app.

Usage:
  arcmark.js <command> [args] [flags]

State:
  state                                Dump the full AppState JSON.
  tree WORKSPACE_ID                    Dump a single workspace tree.

Workspaces (cannot be deleted by the agent):
  workspaces:list
  workspaces:create        --name "X" [--color NAME]
  workspaces:rename ID     --name "Y"
  workspaces:set-color ID  --color NAME

Folders:
  folders:create   --workspace ID [--parent ID|root] --name "X" [--expanded true|false]
  folders:rename   ID  --name "Y"
  folders:delete   ID

Links:
  links:create     --workspace ID [--parent ID|root] --url URL [--title T]
  links:rename     ID  --title "Y"
  links:set-url    ID  --url URL
  links:delete     ID

Notes:
  notes:create     --workspace ID [--parent ID|root] --title T [--content "..." | --file PATH | --content -]
  notes:rename     ID  --title "Y"
  notes:read       ID
  notes:write      ID  --content "..." | --file PATH | --content -
  notes:delete     ID

Generic:
  nodes:move       ID [--to-workspace ID] [--to-parent ID|root] [--index N]
  nodes:delete     ID

Color names: Blush, Apricot, Butter, Leaf, Mint, Sky, Periwinkle, Lavender
(also accepts the raw enum cases ember, ruby, coral, tangerine, moss, ocean, indigo, graphite).

Endpoint file: ${ENDPOINT_FILE}
`;

function cmdHelp() {
  process.stdout.write(HELP);
}

// ---------- Entry ----------

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0) {
    cmdHelp();
    process.exit(0);
  }
  const command = argv[0];
  const handler = COMMANDS[command];
  if (!handler) {
    fail('unknown_command', `Unknown command: ${command}`, { hint: 'Run `arcmark.js help` for the full list.' });
  }
  const args = parseArgs(argv.slice(1));
  try {
    await handler(args);
  } catch (e) {
    fail('internal_error', e.message || String(e));
  }
}

main();
