#!/bin/bash
# Check native token balance for deployer wallet
# Usage: ./balance.sh <CHAIN_ID>
# Example: ./balance.sh 5115

set -e

CHAIN_ID=$1

if [ -z "$CHAIN_ID" ]; then
    echo "Usage: $0 <CHAIN_ID>"
    echo "Example: $0 5115"
    exit 1
fi

# Load .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Get RPC URL
RPC_ENV_VAR="RPC_URL_${CHAIN_ID}"
RPC_URL=$(eval echo \$$RPC_ENV_VAR)

if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL_${CHAIN_ID} not found in .env"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not found in .env"
    exit 1
fi

# Derive address from private key
ADDRESS=$(cast wallet address "$PRIVATE_KEY")

echo "Chain ID : $CHAIN_ID"
echo "RPC URL  : $RPC_URL"
echo "Address  : $ADDRESS"
echo ""

# Get balance
BALANCE_WEI=$(cast balance "$ADDRESS" --rpc-url "$RPC_URL")
BALANCE_ETH=$(cast from-wei "$BALANCE_WEI")

echo "Balance  : $BALANCE_ETH"

