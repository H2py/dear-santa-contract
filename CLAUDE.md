# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dear Santa is a Christmas-themed NFT service that allows users to mint tree NFTs and decorate them with ornament NFTs. The project uses signature-based minting where the backend generates signatures and users execute transactions on-chain.

**Contracts:**
- `TreeNFT` (ERC721): Christmas tree NFTs with customizable backgrounds
- `OrnamentNFT` (ERC1155): Decorative ornaments for trees (both pre-registered and custom)

**Blockchain:** Built for Zeta Chain (default chain ID: 7001) using Foundry framework

## Core Architecture

### Contract Interaction Flow

1. **Tree Minting (Signature-based)**:
   - Backend generates EIP-712 signature with MintPermit (treeId, backgroundId, uri, deadline, nonce)
   - User calls `TreeNFT.mintWithSignature()` with the permit and signature
   - User pays gas; signature ensures backend authorization

2. **Ornament Minting**:
   - **Free Gacha**: Backend signs OrnamentMintPermit for a random registered ornament
   - **Custom Paid**: User directly calls `mintCustomOrnament()` with ERC20 payment

3. **Tree-Ornament Relationship**:
   - Each tree stores ornament IDs in `_treeOrnaments` mapping
   - First 10 ornaments are "display" (MAX_DISPLAY = 10)
   - Additional ornaments go to "reserve" and can be promoted via `promoteOrnaments()`
   - Display order can be rearranged with `setDisplayOrder()`

### EIP-712 Signature Verification

Both contracts use EIP-712 typed data signing:
- **TreeNFT**: Domain name "ZetaTree", version "1"
- **OrnamentNFT**: Domain name "ZetaOrnament", version "1"
- Nonces prevent replay attacks (per-user, incremented on each use)
- Deadline ensures time-limited validity

### Admin Responsibilities

- Register backgrounds before tree minting: `registerBackground()` or `registerBackgrounds()`
- Register ornaments for gacha pool: `registerOrnament()` or `registerOrnaments()`
- Set OrnamentNFT contract address in TreeNFT: `setOrnamentNFT()`
- Configure payment token and mint fee: `setPaymentToken()`, `setMintFee()`
- Moderate inappropriate custom ornaments: `setOrnamentUri()` (change to placeholder)
- Withdraw accumulated fees: `withdrawFees()`

## Development Commands

### Build
```bash
forge build
```

### Test
```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/TreeNFT.t.sol

# Run with verbosity for detailed output
forge test -vvvv

# Run specific test function
forge test --match-test testMintWithSignature
```

### Deployment
```bash
# Deploy to specific chain
./deploy.sh <CHAIN_ID>

# Example: Deploy to Zeta Chain testnet
./deploy.sh 7001
```

### Check Deployer Balance
```bash
./balance.sh <CHAIN_ID>
```

### Environment Variables

Required in `.env`:
```
PRIVATE_KEY=0x...
RPC_URL_7001=https://...
SIGNER_ADDRESS=0x...  # Optional, defaults to deployer address
```

## Key Contract Details

### TreeNFT.sol

**Important Functions:**
- `mintWithSignature(MintPermit, signature)`: Mint tree with backend authorization (src/TreeNFT.sol:61)
- `addOrnamentToTree(treeId, ornamentId)`: Add ornament to tree (src/TreeNFT.sol:143)
- `setDisplayOrder(treeId, newOrder)`: Reorder display ornaments (src/TreeNFT.sol:149)
- `promoteOrnaments(treeId, displayIdxs, reserveIdxs)`: Swap display/reserve ornaments (src/TreeNFT.sol:172)
- `getDisplayOrnaments(treeId)`: Get first 10 ornaments (src/TreeNFT.sol:200)

**State Variables:**
- `MAX_DISPLAY = 10`: Maximum ornaments shown on tree
- `signer`: Address authorized to sign mint permits
- `ornamentNFT`: OrnamentNFT contract address
- `nonces[address]`: Per-user nonce for replay protection
- `treeBackground[treeId]`: Background ID for each tree
- `backgroundRegistered[backgroundId]`: Whether background is registered

### OrnamentNFT.sol

**Important Functions:**
- `mintWithSignature(OrnamentMintPermit, signature)`: Free ornament minting (src/OrnamentNFT.sol:76)
- `mintCustomOrnament(treeId, uri)`: Paid custom ornament (src/OrnamentNFT.sol:105)
- `registerOrnament(tokenId, uri)`: Admin registers ornament for gacha (src/OrnamentNFT.sol:137)

**State Variables:**
- `CUSTOM_TOKEN_START = 1001`: Token IDs >= 1001 are custom ornaments
- `signer`: Address authorized to sign mint permits
- `treeNFT`: TreeNFT contract address
- `paymentToken`: ERC20 token used for custom ornament payments
- `mintFee`: Cost to mint custom ornament
- `nextCustomTokenId`: Next ID for custom ornaments (starts at 1001)
- `ornamentRegistered[tokenId]`: Whether ornament is registered

## Testing Strategy

Tests use Foundry's testing framework with:
- `forge-std/Test.sol` for test utilities
- EIP-712 signature creation using `vm.sign()`
- Address derivation using `vm.addr()`
- Time manipulation with `vm.warp()`

See `test/TreeNFT.t.sol` and `test/OrnamentNFT.t.sol` for examples.

## Backend Integration Notes

**BACKEND_GUIDE.md** contains comprehensive backend integration details in Korean, including:
- TypeScript code examples for EIP-712 signature generation
- API endpoint patterns for mint request handling
- Nonce management and concurrent request handling
- Error handling for all contract revert cases
- Wallet analysis logic for background selection
- Database schema recommendations for signature tracking

When implementing backend features, refer to BACKEND_GUIDE.md for detailed integration patterns.

## Common Error Codes

| Error | Meaning | Resolution |
|-------|---------|------------|
| `InvalidSignature` | Signature verification failed | Regenerate signature with correct signer |
| `ExpiredDeadline` | Signature expired | Request new signature |
| `InvalidNonce` | Nonce mismatch | Fetch latest nonce from contract |
| `BackgroundNotRegistered` | Background not registered | Admin must call `registerBackground()` |
| `OrnamentNotRegistered` | Ornament not in gacha pool | Admin must call `registerOrnament()` |
| `NotTreeOwner` | Caller doesn't own tree | Verify ownership |
| `PaymentTokenNotSet` | Payment token not configured | Admin must call `setPaymentToken()` |
| `MintFeeNotSet` | Mint fee is zero | Admin must call `setMintFee()` |

## Deployment Checklist

Before production deployment:
- [ ] Register all backgrounds using `registerBackgrounds()`
- [ ] Register ornaments for gacha pool using `registerOrnaments()`
- [ ] Set OrnamentNFT address in TreeNFT using `setOrnamentNFT()`
- [ ] Configure payment token using `setPaymentToken()`
- [ ] Set mint fee using `setMintFee()`
- [ ] Verify signer address is correctly set
- [ ] Test signature generation and verification flow
- [ ] Ensure backend nonce tracking is synchronized
