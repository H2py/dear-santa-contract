#!/bin/zsh

# Deploy TreeNFT and OrnamentNFT contracts to specified network
# Usage: ./deploy.sh <chainId>
# Example: ./deploy.sh 7001

set -e

if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh <chainId>"
    echo "Example: ./deploy.sh 7001"
    exit 1
fi

CHAIN_ID=$1

# Load .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Error: .env file not found"
    exit 1
fi

# Check PRIVATE_KEY
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set in .env"
    exit 1
fi

# Get RPC URL for the specified chain
RPC_VAR="RPC_URL_${CHAIN_ID}"
RPC_URL="${(P)RPC_VAR}"

if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL_${CHAIN_ID} not set in .env"
    exit 1
fi

echo "Deploying to Chain ID: $CHAIN_ID"
echo ""

# Deploy contracts (--slow waits for each tx to be confirmed)
echo "Starting deployment... (waiting for transactions to confirm)"
echo ""

if ! forge script script/Deploy.s.sol:Deploy \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --slow; then
    echo ""
    echo "=========================================="
    echo "Deployment FAILED!"
    echo "=========================================="
    exit 1
fi

# Extract addresses from broadcast JSON
BROADCAST_FILE="broadcast/Deploy.s.sol/${CHAIN_ID}/run-latest.json"

if [ ! -f "$BROADCAST_FILE" ]; then
    echo ""
    echo "Error: Broadcast file not found"
    exit 1
fi

# Check if transactions were confirmed
RECEIPTS_COUNT=$(jq '.receipts | length' "$BROADCAST_FILE")
if [ "$RECEIPTS_COUNT" -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "Warning: No receipts found. Transactions may still be pending."
    echo "=========================================="
    exit 1
fi

TREE_IMPL=$(jq -r '.transactions[0].contractAddress' "$BROADCAST_FILE")
TREE_PROXY=$(jq -r '.transactions[1].contractAddress' "$BROADCAST_FILE")
ORNAMENT_IMPL=$(jq -r '.transactions[2].contractAddress' "$BROADCAST_FILE")
ORNAMENT_PROXY=$(jq -r '.transactions[3].contractAddress' "$BROADCAST_FILE")
UNIVERSAL_IMPL=$(jq -r '.transactions[4].contractAddress' "$BROADCAST_FILE")
UNIVERSAL_PROXY=$(jq -r '.transactions[5].contractAddress' "$BROADCAST_FILE")

echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "TreeNFT"
echo "  Implementation: $TREE_IMPL"
echo "  Proxy:          $TREE_PROXY"
echo ""
echo "OrnamentNFT"
echo "  Implementation: $ORNAMENT_IMPL"
echo "  Proxy:          $ORNAMENT_PROXY"
echo ""
echo "UniversalApp"
echo "  Implementation: $UNIVERSAL_IMPL"
echo "  Proxy:          $UNIVERSAL_PROXY"
echo ""
echo "=========================================="
