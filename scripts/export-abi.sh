#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE_ABI_SRC="$ROOT_DIR/out/TreeNFT.sol/TreeNFT.json"
TREE_ABI_DEST="$ROOT_DIR/../src/abi/tree.json"

ORN_ABI_SRC="$ROOT_DIR/out/OrnamentNFT.sol/OrnamentNFT.json"
ORN_ABI_DEST="$ROOT_DIR/../src/abi/ornament.json"

if [[ ! -f "$TREE_ABI_SRC" || ! -f "$ORN_ABI_SRC" ]]; then
  echo "ABI not found. Run 'forge build' first." >&2
  exit 1
fi

mkdir -p "$(dirname "$TREE_ABI_DEST")"
cp "$TREE_ABI_SRC" "$TREE_ABI_DEST"
echo "Copied Tree ABI to $TREE_ABI_DEST"

mkdir -p "$(dirname "$ORN_ABI_DEST")"
cp "$ORN_ABI_SRC" "$ORN_ABI_DEST"
echo "Copied Ornament ABI to $ORN_ABI_DEST"
