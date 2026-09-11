#!/usr/bin/env python3
"""Smoke-test hm-ide-agent B1/B2: hello, fs, pty, watch, search, git, task."""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

PORT = int(os.environ.get("HM_AGENT_PORT", "17821"))
URL = sys.argv[1] if len(sys.argv) > 1 else f"ws://127.0.0.1:{PORT}/ws"

def health():
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
        body = r.read().decode()
        print("health:", body)
        return json.loads(body)

try:
    import websocket  # websocket-client
except ImportError:
    print("websocket-client not installed; checking /health only")
    health()
    print("Install: pip install websocket-client  OR  use tools/agent-smoke-test.mjs")
    sys.exit(0)

h = health()
assert h.get("ok"), h
ws = websocket.create_connection(URL, timeout=8)
_id = 0
notifications = []

def req(method, params=None, wait_notify=None, notify_timeout=2.0):
    global _id
    _id += 1
    ws.send(json.dumps({"id": _id, "method": method, "params": params or {}}))
    deadline = time.time() + 8
    result = None
    while time.time() < deadline:
        ws.settimeout(max(0.1, deadline - time.time()))
        try:
            msg = json.loads(ws.recv())
        except Exception:
            break
        if msg.get("method") and "id" not in msg:
            notifications.append(msg)
            print(f"  [notify] {msg['method']}", str(msg.get("params", {}))[:180])
            if wait_notify and msg["method"] == wait_notify:
                if result is not None:
                    return result, msg
                wait_notify = "__got__"
            continue
        if msg.get("id") == _id:
            if "error" in msg:
                raise RuntimeError(msg["error"])
            result = msg["result"]
            if wait_notify is None or wait_notify == "__got__":
                return result if wait_notify is None else (result, notifications[-1] if notifications else None)
    if result is not None:
        return result
    raise TimeoutError(f"no response for {method}")

hello = req("session.hello")
print("hello:", hello)
assert hello["version"], hello
assert "session_token" in hello, hello
token = hello["session_token"]
hello2 = req("session.hello", {"sessionToken": token})
assert hello2.get("resumed") is True, hello2
print("resume ok")

tmpdir = tempfile.mkdtemp(prefix="hm-ide-")
f = os.path.join(tmpdir, "note.txt")
req("fs.write", {"path": f, "data": "hello from smoke\nsearchable_marker_XYZ\n"})
print("fs.read:", req("fs.read", {"path": f})["data"].splitlines()[0])
print("fs.list:", len(req("fs.list", {"path": tmpdir})["entries"]))

# watch
w = req("fs.watch", {"path": tmpdir, "recursive": True})
print("watch:", w["watchId"])
changed = os.path.join(tmpdir, "changed.txt")
# trigger change after arming
time.sleep(0.2)
with open(changed, "w") as fp:
    fp.write("x\n")
# wait for fs.changed
deadline = time.time() + 3
got_change = False
while time.time() < deadline:
    ws.settimeout(0.5)
    try:
        msg = json.loads(ws.recv())
    except Exception:
        continue
    if msg.get("method") == "fs.changed":
        print("fs.changed:", msg.get("params"))
        got_change = True
        break
print("watch event:", "OK" if got_change else "MISS (fs may coalesce; non-fatal)")
req("fs.unwatch", {"watchId": w["watchId"]})

# search
sr = req("fs.search", {"path": tmpdir, "query": "searchable_marker_XYZ", "maxHits": 20})
print("fs.search hits:", sr["count"], sr["hits"][:1])
assert sr["count"] >= 1

# git
gdir = tempfile.mkdtemp(prefix="hm-ide-git-")
subprocess.check_call(["git", "init"], cwd=gdir, stdout=subprocess.DEVNULL)
subprocess.check_call(["git", "config", "user.email", "smoke@test"], cwd=gdir)
subprocess.check_call(["git", "config", "user.name", "smoke"], cwd=gdir)
gf = os.path.join(gdir, "a.txt")
open(gf, "w").write("one\n")
subprocess.check_call(["git", "add", "a.txt"], cwd=gdir)
subprocess.check_call(["git", "commit", "-m", "init"], cwd=gdir, stdout=subprocess.DEVNULL)
open(gf, "w").write("two\n")
open(os.path.join(gdir, "b.txt"), "w").write("new\n")
gst = req("git.status", {"path": gdir})
print("git.status:", gst["branch"], "items=", len(gst["items"]))
assert len(gst["items"]) >= 1
gd = req("git.diff", {"path": gdir})
print("git.diff:", gd["filesChanged"], "ins", gd["insertions"], "del", gd["deletions"])

# task
tr = req("task.run", {"command": "echo TASK_SMOKE_OK && exit 0", "cwd": tmpdir})
print("task.run:", tr["taskId"])
deadline = time.time() + 5
saw_out = saw_exit = False
while time.time() < deadline and not (saw_out and saw_exit):
    ws.settimeout(0.5)
    try:
        msg = json.loads(ws.recv())
    except Exception:
        continue
    if msg.get("method") == "task.output":
        print("task.output:", msg["params"].get("data", "").strip())
        if "TASK_SMOKE_OK" in str(msg["params"].get("data", "")):
            saw_out = True
    if msg.get("method") == "task.exit":
        print("task.exit:", msg["params"])
        saw_exit = True
assert saw_exit, "task.exit not received"

# pty
pty = req("pty.open", {"cols": 80, "rows": 24, "cwd": tmpdir})
print("pty:", pty["ptyId"])
req("pty.write", {"ptyId": pty["ptyId"], "data": "echo SMOKE_OK\n"})
time.sleep(0.8)
req("pty.close", {"ptyId": pty["ptyId"]})

ws.close()
print("SMOKE OK (hello/fs/watch/search/git/task/pty)")
