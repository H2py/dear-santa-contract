#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ABI_DIR="$PROJECT_ROOT/abi"

TREE_ABI_SRC="$PROJECT_ROOT/out/TreeNFT.sol/TreeNFT.json"
TREE_ABI_DEST="$ABI_DIR/tree-abi.json"

ORN_ABI_SRC="$PROJECT_ROOT/out/OrnamentNFT.sol/OrnamentNFT.json"
ORN_ABI_DEST="$ABI_DIR/ornament-abi.json"

UNIVERSAL_ABI_SRC="$PROJECT_ROOT/out/UniversalApp.sol/UniversalApp.json"
UNIVERSAL_ABI_DEST="$ABI_DIR/universal-app-abi.json"

if ! command -v jq &> /dev/null; then
  echo "jq is required. Install with 'brew install jq'" >&2
  exit 1
fi

if [[ ! -f "$TREE_ABI_SRC" || ! -f "$ORN_ABI_SRC" || ! -f "$UNIVERSAL_ABI_SRC" ]]; then
  echo "ABI not found. Run 'forge build' first." >&2
  exit 1
fi

mkdir -p "$ABI_DIR"

jq '.abi' "$TREE_ABI_SRC" > "$TREE_ABI_DEST"
echo "Exported Tree ABI to $TREE_ABI_DEST"

jq '.abi' "$ORN_ABI_SRC" > "$ORN_ABI_DEST"
echo "Exported Ornament ABI to $ORN_ABI_DEST"

jq '.abi' "$UNIVERSAL_ABI_SRC" > "$UNIVERSAL_ABI_DEST"
echo "Exported UniversalApp ABI to $UNIVERSAL_ABI_DEST"
