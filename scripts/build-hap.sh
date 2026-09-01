#!/usr/bin/env bash
#
# build-hap.sh — get the embedded-Node artifacts ready, then build the HAP.
#
# Requirements (provided by the HarmonyOS SDK / DevEco command line):
#   * Node.js 18+ on PATH (hvigor runs on Node)
#   * HarmonyOS SDK configured (command-line `hvigorw` is used, no IDE needed)
#   * A signing config in build-profile.json5 (or pass signing via -p)
#
# Usage:
#   ./scripts/build-hap.sh arm64      # default
#   ./scripts/build-hap.sh x64        # emulator
set -euo pipefail

ARCH="${1:-arm64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> preparing Node headers"
bash "$ROOT/scripts/prepare-headers.sh"

echo "==> preparing libnode.so ($ARCH)"
bash "$ROOT/scripts/prepare-node.sh" "$ARCH"

echo "==> building HAP"
if [ ! -x "$ROOT/hvigorw" ]; then
  echo "hvigorw not found — open the project in DevEco Studio and build, or run:" >&2
  echo "  hvigorw assembleHap --mode module -p product=default" >&2
  exit 1
fi

"$ROOT/hvigorw" assembleHap --mode module -p module=entry@default -p product=default --analyze=normal
echo "==> done"
