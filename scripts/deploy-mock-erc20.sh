#!/bin/zsh

# Deploy MockERC20 token
# Usage: ./scripts/deploy-mock-erc20.sh <chainId>
# Example: ./scripts/deploy-mock-erc20.sh 7001

set -e

if [ -z "$1" ]; then
    echo "Usage: ./scripts/deploy-mock-erc20.sh <chainId>"
    echo "Example: ./scripts/deploy-mock-erc20.sh 7001"
    exit 1
fi

CHAIN_ID=$1
TOKEN_NAME="Mock USDC"
TOKEN_SYMBOL="USDC"

# Load .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Error: .env file not found"
    exit 1
fi

# Export token name and symbol as environment variables for the script
export MOCK_TOKEN_NAME="$TOKEN_NAME"
export MOCK_TOKEN_SYMBOL="$TOKEN_SYMBOL"

# Check PRIVATE_KEY
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set in .env"
    exit 1
fi

# Get RPC URL based on chain ID
case $CHAIN_ID in
    7001)
        RPC_URL="https://zetachain-athens-evm.blockpi.network/v1/rpc/public"
        EXPLORER="https://zetachain-athens-3.blockscout.com"
        ;;
    7000)
        RPC_URL="https://zetachain-evm.blockpi.network/v1/rpc/public"
        EXPLORER="https://explorer.zetachain.com"
        ;;
    84532)
        RPC_URL="https://sepolia.base.org"
        EXPLORER="https://sepolia.basescan.org"
        ;;
    8453)
        RPC_URL="https://mainnet.base.org"
        EXPLORER="https://basescan.org"
        ;;
    *)
        echo "Error: Unsupported chain ID: $CHAIN_ID"
        echo "Supported chains: 7001 (ZetaChain Testnet), 7000 (ZetaChain Mainnet), 84532 (Base Sepolia), 8453 (Base Mainnet)"
        exit 1
        ;;
esac

echo "Deploying MockERC20 to chain $CHAIN_ID..."
echo "Token Name: $TOKEN_NAME"
echo "Token Symbol: $TOKEN_SYMBOL"
echo "RPC URL: $RPC_URL"
echo ""

# Deploy with optional verification
if [ -n "$ETHERSCAN_API_KEY" ]; then
    echo "Verification enabled (ETHERSCAN_API_KEY found)"
    forge script script/DeployMockERC20.s.sol:DeployMockERC20 \
        --rpc-url $RPC_URL \
        --broadcast \
        --verify \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        -vvvv
else
    echo "Verification skipped (ETHERSCAN_API_KEY not set)"
    forge script script/DeployMockERC20.s.sol:DeployMockERC20 \
        --rpc-url $RPC_URL \
        --broadcast \
        -vvvv
fi

echo ""
echo "✅ MockERC20 deployment complete!"
echo ""
echo "To mint tokens, run:"
echo "  ./scripts/mint-mock-erc20.sh $CHAIN_ID <TOKEN_ADDRESS> <RECIPIENT_ADDRESS>"

