#!/usr/bin/env bash
# Cross-compile libgit2 for HarmonyOS NDK (arm64-v8a).
# Usage:
#   export OHOS_NDK=/path/to/command-line-tools/sdk/default/openharmony/native
#   ./native/scripts/build-libgit2-ohos.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ROOT}/native/third_party/libgit2-ohos"
SRC="${ROOT}/native/third_party/libgit2-src"
: "${OHOS_NDK:?Set OHOS_NDK to HarmonyOS native SDK}"

if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 --branch v1.7.2 https://github.com/libgit2/libgit2.git "$SRC"
fi

TOOLCHAIN="${OHOS_NDK}/build/cmake/ohos.toolchain.cmake"
if [[ ! -f "$TOOLCHAIN" ]]; then
  echo "Missing toolchain: $TOOLCHAIN" >&2
  echo "Adjust path for your DevEco SDK layout." >&2
  exit 1
fi

BUILD="${ROOT}/native/third_party/libgit2-build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DOHOS_ARCH=arm64-v8a \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_CLI=OFF \
  -DUSE_SSH=OFF \
  -DUSE_HTTPS=OFF \
  -DCMAKE_INSTALL_PREFIX="$OUT"
cmake --build "$BUILD" -j"$(nproc)"
cmake --install "$BUILD"
echo "Installed to $OUT"
echo "Add to externalNativeOptions.arguments: -DHM_GIT2_ROOT=$OUT"
