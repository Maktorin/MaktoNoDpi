#!/usr/bin/env bash
# build-tpws.sh — builds a universal (arm64 + x86_64) tpws binary for macOS
# from the zapret project (https://github.com/bol-van/zapret) and installs it
# to App/MaktoNoDpi/Resources/bin/tpws relative to the repo root.
#
# Usage:  bash scripts/build-tpws.sh  (run from repo root)
#
# Requirements: clang (Xcode CLT), lipo, git, make

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${REPO_ROOT}/App/MaktoNoDpi/Resources/bin"
INSTALL_PATH="${INSTALL_DIR}/tpws"
ZAPRET_URL="https://github.com/bol-van/zapret"
WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "==> Working directory: ${WORK_DIR}"
echo "==> Install target:    ${INSTALL_PATH}"
echo ""

# ── 1. Clone zapret (shallow) ────────────────────────────────────────────────
echo "==> Cloning zapret (shallow)…"
git clone --depth=1 "${ZAPRET_URL}" "${WORK_DIR}/zapret"
TPWS_DIR="${WORK_DIR}/zapret/tpws"
cd "${TPWS_DIR}"

# ── 2. Attempt universal (arm64 + x86_64) build via the top-level mac target ─
# The top-level Makefile's `mac` target delegates to tpws/Makefile `mac`,
# which compiles tpwsa (arm64) and tpwsx (x86_64) then lipo-merges them.
# We run it directly inside tpws/ to avoid the top-level mv/symlink dance.

echo "==> Building tpws for macOS (universal arm64+x86_64)…"

UNIVERSAL=true
if make mac 2>&1; then
    echo "==> Universal build succeeded."
else
    echo "==> Universal build failed — falling back to arm64-only…"
    UNIVERSAL=false
    # Clean any partial artefacts
    rm -f tpws tpwsa tpwsx
    # arm64-only build using the same flags as the mac target
    cc -std=gnu99 -Os -flto=auto -ffunction-sections -fdata-sections \
        -Wno-address-of-packed-member \
        -Iepoll-shim/include -Imacos \
        -target arm64-apple-macos10.8 \
        -o tpws \
        *.c epoll-shim/src/*.c \
        -lz -lpthread \
        -flto=auto -Wl,-dead_strip
    strip tpws
    echo "==> arm64-only build succeeded."
fi

# ── 3. Verify we have a Mach-O binary ────────────────────────────────────────
if [[ ! -f tpws ]]; then
    echo "ERROR: tpws binary not found after build." >&2
    exit 1
fi

FILE_OUT="$(file tpws)"
echo "==> file output: ${FILE_OUT}"

if ! echo "${FILE_OUT}" | grep -q "Mach-O"; then
    echo "ERROR: output is not a Mach-O binary." >&2
    exit 1
fi

# ── 4. Install ────────────────────────────────────────────────────────────────
mkdir -p "${INSTALL_DIR}"
cp tpws "${INSTALL_PATH}"
chmod 755 "${INSTALL_PATH}"

echo ""
echo "==> Installed: ${INSTALL_PATH}"
echo "==> file: $(file "${INSTALL_PATH}")"
echo "==> Arches: $(lipo -archs "${INSTALL_PATH}" 2>/dev/null || echo 'single-arch')"
echo ""
echo "==> Universal build: ${UNIVERSAL}"
echo "DONE."
