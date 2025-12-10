#!/bin/zsh

# Mint MockERC20 tokens to a recipient address
# Usage: ./scripts/mint-mock-erc20.sh <chainId> <tokenAddress> <recipientAddress>
# Example: ./scripts/mint-mock-erc20.sh 7001 0x1234... 0xabcd...

set -e

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: ./scripts/mint-mock-erc20.sh <chainId> <tokenAddress> <recipientAddress>"
    echo "Example: ./scripts/mint-mock-erc20.sh 7001 0x1234... 0xabcd..."
    exit 1
fi

CHAIN_ID=$1
TOKEN_ADDRESS=$2
RECIPIENT_ADDRESS=$3

# Load .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Error: .env file not found"
    exit 1
fi

# Export parameters as environment variables for the script
export MOCK_ERC20_ADDRESS="$TOKEN_ADDRESS"
export RECIPIENT_ADDRESS="$RECIPIENT_ADDRESS"

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

echo "Minting MockERC20 tokens..."
echo "Chain ID: $CHAIN_ID"
echo "Token Address: $TOKEN_ADDRESS"
echo "Recipient Address: $RECIPIENT_ADDRESS"
echo ""

# Mint tokens
forge script script/MintMockERC20.s.sol:MintMockERC20 \
    --rpc-url $RPC_URL \
    --broadcast \
    -vvvv \
    --sig "run()"

echo ""
echo "✅ Minting complete!"
echo "Recipient should now have 100 MockERC20 tokens (100 * 10^6)"

