#!/usr/bin/env bash
#
# prepare-node.sh — download the prebuilt shared libnode.so for the target ABI
# and drop it where the HarmonyOS build expects it.
#
# Usage:
#   ./scripts/prepare-node.sh arm64      # device (arm64-v8a)
#   ./scripts/prepare-node.sh x64        # emulator / x86_64
#
# The artifact is verified against a pinned SHA-256 and a PIE (bad) build is
# rejected outright — only a true `--shared` .so will run inside the app.
set -euo pipefail

ARCH="${1:-arm64}"
RELEASE_REPO="${RELEASE_REPO:-electerm/ohos-node-shared}"
VERSION="${VERSION:-ohos-node-shared-v24.2.0}"

case "$ARCH" in
  arm64) ABI="arm64-v8a"; ASSET="libnode-arm64.so"; SHA="3019bf5f9a279d98a87606fc13c53b0e797b6a50cf174f8a1243d880c71151a1" ;;
  x64)   ABI="x86_64";     ASSET="libnode-x64.so";   SHA="d001ec8b34db459d45ce5f1b8952b49fc55ac0b5e0a5d2b77193f6a1a3608990" ;;
  *) echo "unknown arch '$ARCH' (use arm64 or x64)" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT/entry/libs/$ABI"
DEST="$DEST_DIR/libnode.so"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$DEST_DIR"
URL="https://github.com/$RELEASE_REPO/releases/download/$VERSION/$ASSET"
echo "downloading $ASSET ($VERSION) -> $DEST"
curl -fL "$URL" -o "$TMP/$ASSET"

echo "verifying sha256..."
ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{print $1}')"
if [ "$ACTUAL" != "$SHA" ]; then
  echo "sha256 mismatch: expected $SHA got $ACTUAL" >&2
  exit 1
fi

# Reject a PIE artifact: a valid shared object must be ET_DYN with no
# PT_INTERP program header.  Parse the ELF header in Python (no binutils needed).
if command -v python3 >/dev/null 2>&1; then
  python3 - "$TMP/$ASSET" <<'PY'
import sys, struct
path = sys.argv[1]
with open(path, 'rb') as f:
    data = f.read(20)
if data[:4] != b'\x7fELF':
    print('not an ELF file'); sys.exit(1)
e_type, = struct.unpack_from('<H', data, 16)
has_interp = b'\x03\x00\x01\x00' in open(path, 'rb').read()  # PT_INTERP = 3
if e_type != 3 or has_interp:
    print('PIE / non-shared libnode.so rejected (e_type=%d, interp=%s)' % (e_type, has_interp))
    sys.exit(1)
PY
fi

cp "$TMP/$ASSET" "$DEST"
chmod 0644 "$DEST"
echo "ok: $DEST"
