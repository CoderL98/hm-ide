#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist

echo "==> host release (x86_64)"
cargo build --release
HOST_ARCH=$(uname -m)
cp -f target/release/hm-ide-agent "dist/hm-ide-agent-${HOST_ARCH}-linux"
ln -sfn "hm-ide-agent-${HOST_ARCH}-linux" dist/hm-ide-agent
echo "  -> dist/hm-ide-agent-${HOST_ARCH}-linux"

echo "==> aarch64-unknown-linux-gnu (best-effort)"
if rustup target list --installed | grep -q aarch64-unknown-linux-gnu; then
  if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
    cargo build --release --target aarch64-unknown-linux-gnu
    cp -f target/aarch64-unknown-linux-gnu/release/hm-ide-agent dist/hm-ide-agent-aarch64-linux
    echo "  -> dist/hm-ide-agent-aarch64-linux"
  else
    echo "  SKIP: aarch64-linux-gnu-gcc not found"
  fi
else
  echo "  SKIP: rustup target aarch64-unknown-linux-gnu not installed"
fi

ls -la dist/
