#!/usr/bin/env bash
# Host-side helper: upload hm-ide-agent via scp, start with nohup, open LocalForward.
# Prefer tools/hm-ssh-helper when built; otherwise pure OpenSSH.
# Steps: detect arch → upload → install → start → LocalForward → hello.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST=""
PORT=22
USER_NAME=""
REMOTE_PATH=""
AGENT_PORT=17821
TOKEN=""
FORCE=0
IDENTITY=""
BINARY=""
NO_FORWARD=0
EXPECTED_VERSION=""

usage() {
  cat <<USAGE
Usage: $0 -h HOST -u USER -r REMOTE_PATH [options]

Options:
  -h HOST           SSH host
  -p PORT           SSH port (default 22)
  -u USER           SSH user
  -i IDENTITY       SSH identity file
  -r REMOTE_PATH    Remote folder to open (informational / cwd)
  -a AGENT_PORT     Agent listen port (default 17821)
  -t TOKEN          Optional agent --token
  -b BINARY         Local agent binary (default: auto by remote uname -m)
  -f                Force re-upload even if version matches
  -n                Do not open LocalForward (upload+start only)
  -e VERSION        Expected agent version (default: from agent Cargo.toml)
USAGE
}

while getopts "h:p:u:i:r:a:t:b:e:fn" opt; do
  case "$opt" in
    h) HOST="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    u) USER_NAME="$OPTARG" ;;
    i) IDENTITY="$OPTARG" ;;
    r) REMOTE_PATH="$OPTARG" ;;
    a) AGENT_PORT="$OPTARG" ;;
    t) TOKEN="$OPTARG" ;;
    b) BINARY="$OPTARG" ;;
    e) EXPECTED_VERSION="$OPTARG" ;;
    f) FORCE=1 ;;
    n) NO_FORWARD=1 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$HOST" || -z "$USER_NAME" ]]; then
  usage
  exit 1
fi

if [[ -z "$EXPECTED_VERSION" ]]; then
  EXPECTED_VERSION="$(grep -m1 '^version' "$ROOT/agent/Cargo.toml" | sed 's/.*"\(.*\)"/\1/')"
fi

HELPER=""
if [[ -x "$ROOT/tools/hm-ssh-helper/hm-ssh-helper" ]]; then
  HELPER="$ROOT/tools/hm-ssh-helper/hm-ssh-helper"
elif [[ -x "$ROOT/tools/hm-ssh-helper/target/release/hm-ssh-helper" ]]; then
  HELPER="$ROOT/tools/hm-ssh-helper/target/release/hm-ssh-helper"
fi
if [[ -n "$HELPER" ]]; then
  echo "==> using hm-ssh-helper"
  ARGS=(deploy --host "$HOST" --port "$PORT" --user "$USER_NAME" --agent-port "$AGENT_PORT")
  [[ -n "$IDENTITY" ]] && ARGS+=(--identity "$IDENTITY")
  [[ -n "$REMOTE_PATH" ]] && ARGS+=(--remote-path "$REMOTE_PATH")
  [[ -n "$TOKEN" ]] && ARGS+=(--token "$TOKEN")
  [[ -n "$BINARY" ]] && ARGS+=(--binary "$BINARY")
  [[ "$FORCE" -eq 1 ]] && ARGS+=(--force)
  [[ "$NO_FORWARD" -eq 1 ]] && ARGS+=(--no-forward)
  exec "$HELPER" "${ARGS[@]}"
fi

SSH=(ssh -p "$PORT" -o StrictHostKeyChecking=accept-new)
SCP=(scp -P "$PORT" -o StrictHostKeyChecking=accept-new)
if [[ -n "$IDENTITY" ]]; then
  SSH+=(-i "$IDENTITY")
  SCP+=(-i "$IDENTITY")
fi
TARGET="${USER_NAME}@${HOST}"

echo "[detect] remote arch via ssh…"
REMOTE_ARCH="$("${SSH[@]}" "$TARGET" 'uname -m')"
case "$REMOTE_ARCH" in
  x86_64|amd64) ARCH_TAG=x86_64 ;;
  aarch64|arm64) ARCH_TAG=aarch64 ;;
  *) echo "unsupported remote arch: $REMOTE_ARCH"; exit 1 ;;
esac

if [[ -z "$BINARY" ]]; then
  BINARY="$ROOT/agent/dist/hm-ide-agent-${ARCH_TAG}-linux"
fi
if [[ ! -x "$BINARY" ]]; then
  echo "missing binary: $BINARY (build agent first)"
  exit 1
fi

REMOTE_DIR='$HOME/.hm-ide-agent/bin'
REMOTE_BIN='$HOME/.hm-ide-agent/bin/hm-ide-agent'

echo "[detect] arch=$REMOTE_ARCH binary=$BINARY expected_version=$EXPECTED_VERSION"
"${SSH[@]}" "$TARGET" "mkdir -p ${REMOTE_DIR}"

NEED_UPLOAD=1
if [[ "$FORCE" -eq 0 ]]; then
  REMOTE_VER="$("${SSH[@]}" "$TARGET" "curl -s http://127.0.0.1:${AGENT_PORT}/health 2>/dev/null || true" || true)"
  if echo "$REMOTE_VER" | grep -q "\"version\":\"${EXPECTED_VERSION}\""; then
    echo "[version] remote agent already v${EXPECTED_VERSION}"
    NEED_UPLOAD=0
  elif "${SSH[@]}" "$TARGET" "test -x ${REMOTE_BIN}"; then
    # binary exists but version unknown / mismatch → upload
    echo "[version] binary exists but health version mismatch or agent down → re-upload"
    NEED_UPLOAD=1
  fi
fi

if [[ "$NEED_UPLOAD" -eq 1 || "$FORCE" -eq 1 ]]; then
  echo "[upload] scp…"
  "${SCP[@]}" "$BINARY" "${TARGET}:${REMOTE_BIN}.new"
  "${SSH[@]}" "$TARGET" "chmod +x ${REMOTE_BIN}.new && mv -f ${REMOTE_BIN}.new ${REMOTE_BIN}"
  echo "[install] ~/.hm-ide-agent/bin/hm-ide-agent"
fi

TOKEN_ARG=""
if [[ -n "$TOKEN" ]]; then
  TOKEN_ARG="--token ${TOKEN}"
fi

echo "[start] agent on 127.0.0.1:${AGENT_PORT}"
HEALTH="$("${SSH[@]}" "$TARGET" "pkill -f '[h]m-ide-agent' || true; nohup ${REMOTE_BIN} --port ${AGENT_PORT} ${TOKEN_ARG} >\$HOME/.hm-ide-agent/agent.log 2>&1 & sleep 0.4; curl -s http://127.0.0.1:${AGENT_PORT}/health || true")"
echo "[hello] ${HEALTH}"

if ! echo "$HEALTH" | grep -q "\"version\":\"${EXPECTED_VERSION}\""; then
  echo "[warn] version check failed (got: ${HEALTH}); try -f to force upload"
fi

echo "[ws] IDE WS: ws://127.0.0.1:${AGENT_PORT}/ws"
if [[ -n "$REMOTE_PATH" ]]; then
  echo "[path] Open remote path: ${REMOTE_PATH}"
fi

if [[ "$NO_FORWARD" -eq 1 ]]; then
  echo "[forward] skipped (-n)"
  exit 0
fi

echo "[forward] LocalForward 127.0.0.1:${AGENT_PORT} (keep session open)"
exec "${SSH[@]}" -N -L "127.0.0.1:${AGENT_PORT}:127.0.0.1:${AGENT_PORT}" "$TARGET"
