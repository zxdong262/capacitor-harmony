#!/usr/bin/env bash
#
# prepare-headers.sh — fetch the Node.js v24.2.0 C/C++ headers needed to compile
# the embedded-Node glue (capacitor_node.cpp).
#
# Downloads the official `node-headers.tar.gz`, which contains the exact
# `include/node/{node.h, v8.h, uv.h, libplatform/...}` layout our CMakeLists
# expects, then lays it out under entry/node-headers/include.
set -euo pipefail

NODE_VERSION="${NODE_VERSION:-v24.2.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/entry/node-headers"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"
URL="https://nodejs.org/dist/$NODE_VERSION/node-headers.tar.gz"
echo "downloading $URL"
curl -fL "$URL" -o "$TMP/node-headers.tar.gz"
tar -xzf "$TMP/node-headers.tar.gz" -C "$TMP"

# node-headers.tar.gz extracts to a single dir (e.g. node-v24.2.0) that
# already contains include/node/...
SRC="$(find "$TMP" -maxdepth 1 -type d -name 'node-*' | head -n1)"
if [ -z "$SRC" ]; then
  echo "could not locate extracted node-headers" >&2
  exit 1
fi

rm -rf "$OUT/include"
cp -R "$SRC/include" "$OUT/include"
echo "ok: headers at $OUT/include"
