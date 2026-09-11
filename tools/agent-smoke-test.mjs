#!/usr/bin/env node
/** Smoke-test hm-ide-agent B1/B2 (Node). */
import WebSocket from 'ws';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { execSync } from 'child_process';
import http from 'http';

const PORT = process.env.HM_AGENT_PORT || '17821';
const URL = process.argv[2] || `ws://127.0.0.1:${PORT}/ws`;

function health() {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${PORT}/health`, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => resolve(JSON.parse(d)));
    }).on('error', reject);
  });
}

const h = await health();
console.log('health:', h);

const ws = new WebSocket(URL);
await new Promise((r, j) => { ws.once('open', r); ws.once('error', j); });
let id = 0;
const pending = new Map();
const notif = [];
ws.on('message', (raw) => {
  const msg = JSON.parse(String(raw));
  if (msg.method && msg.id === undefined) {
    notif.push(msg);
    console.log('[notify]', msg.method, JSON.stringify(msg.params).slice(0, 120));
    return;
  }
  const p = pending.get(msg.id);
  if (!p) return;
  pending.delete(msg.id);
  if (msg.error) p.reject(new Error(JSON.stringify(msg.error)));
  else p.resolve(msg.result);
});
function req(method, params = {}) {
  const i = ++id;
  ws.send(JSON.stringify({ id: i, method, params }));
  return new Promise((resolve, reject) => {
    pending.set(i, { resolve, reject });
    setTimeout(() => reject(new Error('timeout ' + method)), 8000);
  });
}

const hello = await req('session.hello');
console.log('hello', hello.version, hello.session_token?.slice(0, 8));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hm-ide-'));
const f = path.join(tmp, 'note.txt');
await req('fs.write', { path: f, data: 'hello\nMARKER_ABC\n' });
console.log('read', (await req('fs.read', { path: f })).data.trim().split('\n')[0]);
const w = await req('fs.watch', { path: tmp, recursive: true });
fs.writeFileSync(path.join(tmp, 'x.txt'), 'y');
await new Promise((r) => setTimeout(r, 800));
await req('fs.unwatch', { watchId: w.watchId });
const sr = await req('fs.search', { path: tmp, query: 'MARKER_ABC' });
console.log('search', sr.count);
const gdir = fs.mkdtempSync(path.join(os.tmpdir(), 'hm-ide-git-'));
execSync('git init && git config user.email t@t && git config user.name t', { cwd: gdir });
fs.writeFileSync(path.join(gdir, 'a.txt'), '1\n');
execSync('git add a.txt && git commit -m i', { cwd: gdir });
fs.writeFileSync(path.join(gdir, 'a.txt'), '2\n');
console.log('git', await req('git.status', { path: gdir }));
const tr = await req('task.run', { command: 'echo OK', cwd: tmp });
await new Promise((r) => setTimeout(r, 1000));
console.log('task', tr.taskId);
const pty = await req('pty.open', { cols: 80, rows: 24, cwd: tmp });
await req('pty.close', { ptyId: pty.ptyId });
ws.close();
console.log('SMOKE OK');
process.exit(0);
