#!/usr/bin/env node
// Prototype server for the penny skill: serves a directory of HTML
// over loopback, records which option the user clicked, and reloads the tab
// when we write a new screen.
//
// Configuration is entirely by environment (start.sh sets it):
//   SDD_CONTENT_DIR  directory to serve            (required)
//   SDD_STATE_DIR    pid/log/key/port/events       (required)
//   SDD_HOST         bind address                  (default 127.0.0.1)
//   SDD_PORT         fixed port                    (default: reuse, else random)
//   SDD_IDLE_MS      shut down after this idle     (default 4h)
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CONTENT_DIR = path.resolve(required('SDD_CONTENT_DIR'));
const STATE_DIR = path.resolve(required('SDD_STATE_DIR'));
const HOST = process.env.SDD_HOST || '127.0.0.1';
const IDLE_MS = Number(process.env.SDD_IDLE_MS || 4 * 60 * 60 * 1000);
const ASSET_DIR = __dirname;

function required(name) {
  const v = process.env[name];
  if (!v) {
    process.stdout.write(JSON.stringify({ error: `${name} is not set` }) + '\n');
    process.exit(1);
  }
  return v;
}

fs.mkdirSync(CONTENT_DIR, { recursive: true });
fs.mkdirSync(STATE_DIR, { recursive: true });

// ---------- session key ----------
// The prototype is reachable by any process that can open a loopback socket.
// The key is what separates the user's browser from everything else on the
// box; it rides the URL as ?key= and is mirrored into a cookie so that
// stylesheets, scripts and fetches carry it without us rewriting any HTML.
// Persisted so a restart keeps an already-open tab valid.
const KEY_FILE = path.join(STATE_DIR, 'key');
const PORT_FILE = path.join(STATE_DIR, 'port');
const EVENTS_FILE = path.join(STATE_DIR, 'events');

const KEY = readOrCreate(KEY_FILE, () => crypto.randomBytes(18).toString('hex'));

function readOrCreate(file, make) {
  try {
    const v = fs.readFileSync(file, 'utf8').trim();
    if (v) return v;
  } catch { /* first run */ }
  const v = make();
  fs.writeFileSync(file, v + '\n', { mode: 0o600 });
  return v;
}

function preferredPort() {
  if (process.env.SDD_PORT) return Number(process.env.SDD_PORT);
  try {
    const p = Number(fs.readFileSync(PORT_FILE, 'utf8').trim());
    if (p >= 1024 && p <= 65535) return p;
  } catch { /* no previous run */ }
  return 0; // let the OS pick, then remember it
}

// timingSafeEqual throws on a length mismatch, which itself leaks length —
// hash both sides first so the comparison is always over 32 equal bytes.
function sameSecret(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const ha = crypto.createHash('sha256').update(a).digest();
  const hb = crypto.createHash('sha256').update(b).digest();
  return crypto.timingSafeEqual(ha, hb);
}

function cookieKey(header) {
  for (const part of (header || '').split(';')) {
    const [k, ...rest] = part.trim().split('=');
    if (k === 'sdd_key') return decodeURIComponent(rest.join('='));
  }
  return null;
}

// ---------- content ----------
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
  '.ico': 'image/x-icon',
};

// Bounded so a stray node_modules inside the content dir cannot stall a poll.
function walk(dir, out = [], budget = { n: 2000 }) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    if (budget.n-- <= 0) return out;
    if (e.name.startsWith('.')) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, out, budget);
    else if (e.isFile()) out.push(full);
  }
  return out;
}

function contentStamp() {
  let newest = 0;
  for (const f of walk(CONTENT_DIR)) {
    const m = fs.statSync(f).mtimeMs;
    if (m > newest) newest = m;
  }
  return Math.round(newest);
}

// `/` is always the newest screen. That is what lets us write a new file and
// have the user's open tab land on it — the poll sees the stamp move, the tab
// reloads `/`, and `/` is now the new screen. An explicit path is never
// redirected: a live prototype the user is clicking through must stay put.
function newestHtml() {
  let best = null;
  let bestTime = -1;
  for (const f of walk(CONTENT_DIR)) {
    if (path.extname(f) !== '.html') continue;
    const m = fs.statSync(f).mtimeMs;
    if (m > bestTime) { bestTime = m; best = f; }
  }
  return best;
}

function resolveInContent(urlPath) {
  const rel = decodeURIComponent(urlPath).replace(/^\/+/, '');
  const full = path.resolve(CONTENT_DIR, rel);
  if (full !== CONTENT_DIR && !full.startsWith(CONTENT_DIR + path.sep)) return null;
  try {
    if (fs.statSync(full).isDirectory()) {
      const index = path.join(full, 'index.html');
      return fs.existsSync(index) ? index : null;
    }
    return full;
  } catch {
    return null;
  }
}

// ---------- responses ----------
function headers(type, extra = {}) {
  return {
    'content-type': type,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    // The prototype is ours and loopback-only; framing it elsewhere is a
    // clickjacking surface for zero benefit.
    'x-frame-options': 'DENY',
    ...extra,
  };
}

function send(res, code, type, body, extra) {
  res.writeHead(code, headers(type, extra));
  res.end(body);
}

function sendFile(res, file, extra) {
  const type = TYPES[path.extname(file)] || 'application/octet-stream';
  let body;
  try {
    body = fs.readFileSync(file);
  } catch {
    return send(res, 404, 'text/plain; charset=utf-8', 'not found');
  }
  // Every served page gets the client: click capture and the reload poll.
  if (type.startsWith('text/html')) {
    body = body.toString('utf8').replace(
      /<\/body>/i,
      '<script src="/_sdd/client.js"></script></body>'
    );
    if (!body.includes('/_sdd/client.js')) body += '\n<script src="/_sdd/client.js"></script>\n';
  }
  send(res, 200, type, body, extra);
}

// ---------- request handling ----------
let lastActivity = Date.now();

const server = http.createServer((req, res) => {
  lastActivity = Date.now();
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const viaQuery = url.searchParams.get('key');
  const authorized = sameSecret(viaQuery, KEY) || sameSecret(cookieKey(req.headers.cookie), KEY);

  if (!authorized) return send(res, 403, 'text/plain; charset=utf-8', 'forbidden');

  // Hand the key to the browser once so subresources and fetches carry it.
  const setCookie = viaQuery
    ? { 'set-cookie': `sdd_key=${encodeURIComponent(KEY)}; Path=/; SameSite=Strict; HttpOnly` }
    : {};

  if (url.pathname === '/_sdd/poll') {
    return send(res, 200, TYPES['.json'], JSON.stringify({ stamp: contentStamp() }), setCookie);
  }

  if (url.pathname === '/_sdd/event') {
    if (req.method !== 'POST') return send(res, 405, 'text/plain; charset=utf-8', 'POST only');
    let body = '';
    req.on('data', (c) => {
      body += c;
      if (body.length > 8192) req.destroy(); // a click record is never this big
    });
    req.on('end', () => {
      let payload;
      try {
        payload = JSON.parse(body);
      } catch {
        return send(res, 400, 'text/plain; charset=utf-8', 'bad json');
      }
      const line = JSON.stringify({ ...payload, ts: new Date().toISOString() });
      fs.appendFileSync(EVENTS_FILE, line + '\n');
      send(res, 200, TYPES['.json'], '{"ok":true}', setCookie);
    });
    return;
  }

  if (url.pathname === '/_sdd/client.js' || url.pathname === '/_sdd/frame.css') {
    return sendFile(res, path.join(ASSET_DIR, path.basename(url.pathname)), setCookie);
  }

  const file = url.pathname === '/' ? newestHtml() : resolveInContent(url.pathname);
  if (!file && url.pathname === '/favicon.ico') {
    // Otherwise every screen logs a 404, and the console is where we read the
    // prototype's own errors from.
    res.writeHead(204, headers('image/x-icon', setCookie));
    return res.end();
  }
  if (!file) {
    return send(
      res,
      404,
      'text/plain; charset=utf-8',
      url.pathname === '/' ? 'no screen written yet' : 'not found',
      setCookie
    );
  }
  sendFile(res, file, setCookie);
});

setInterval(() => {
  if (Date.now() - lastActivity > IDLE_MS) process.exit(0);
}, 60_000).unref();

// 'listening' rather than a listen() callback: the EADDRINUSE path below
// re-listens, and a callback passed to the first listen() would not fire again.
server.on('listening', () => {
  const port = server.address().port;
  fs.writeFileSync(PORT_FILE, port + '\n');
  process.stdout.write(
    JSON.stringify({
      type: 'server-started',
      url: `http://${HOST}:${port}/?key=${KEY}`,
      port,
      content_dir: CONTENT_DIR,
      state_dir: STATE_DIR,
      events: EVENTS_FILE,
    }) + '\n'
  );
});

server.listen(preferredPort(), HOST);

server.on('error', (err) => {
  // A stale port file points at a port someone else took; forget it and retry.
  if (err.code === 'EADDRINUSE' && !process.env.SDD_PORT) {
    try { fs.unlinkSync(PORT_FILE); } catch { /* already gone */ }
    server.listen(0, HOST);
    return;
  }
  process.stdout.write(JSON.stringify({ error: String(err.message || err) }) + '\n');
  process.exit(1);
});
