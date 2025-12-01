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

echo "=========================================="
echo "Deploying to Chain ID: $CHAIN_ID"
echo "RPC URL: $RPC_URL"
echo "=========================================="

# Deploy contracts
forge script script/Deploy.s.sol:Deploy \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvvv

echo "=========================================="
echo "Deployment complete!"
echo "=========================================="

