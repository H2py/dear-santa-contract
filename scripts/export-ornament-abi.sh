#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABI_SRC="$ROOT_DIR/out/OrnamentNFT.sol/OrnamentNFT.json"
ABI_DEST="$ROOT_DIR/../src/abi/ornament.json"

if [[ ! -f "$ABI_SRC" ]]; then
  echo "ABI not found at $ABI_SRC. Run 'forge build' first." >&2
  exit 1
fi

mkdir -p "$(dirname "$ABI_DEST")"
cp "$ABI_SRC" "$ABI_DEST"
echo "Copied ABI to $ABI_DEST"
