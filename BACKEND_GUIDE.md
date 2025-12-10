# Dear Santa 백엔드 가이드라인

이 문서는 Dear Santa 서비스의 백엔드에서 스마트 컨트랙트와 상호작용하는 방법을 설명합니다.

## 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [컨트랙트 주소](#컨트랙트-주소)
3. [게임 룰](#게임-룰)
4. [Tree NFT 민팅](#tree-nft-민팅)
5. [Ornament NFT 무료 뽑기](#ornament-nft-무료-뽑기)
6. [Ornament NFT 커스텀 (관리자 전용)](#ornament-nft-커스텀-관리자-전용)
7. [오너먼트 장착 (소각)](#오너먼트-장착-소각)
8. [크로스체인 호출 (Base → ZetaChain)](#크로스체인-호출-base--zetachain)
9. [Nonce 관리](#nonce-관리)
10. [관리자 기능](#관리자-기능)
11. [에러 핸들링](#에러-핸들링)

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────────┐
│                           BASE CHAIN                                │
│  ┌─────────────┐                                                    │
│  │   User TX   │ ─────► Gateway.call() / depositAndCall()           │
│  └─────────────┘         (EIP-7702 sponsored)                       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ Cross-chain message
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         ZETACHAIN                                   │
│  ┌─────────────────┐      ┌───────────────┐      ┌────────────────┐ │
│  │ ZetaChain       │      │               │      │                │ │
│  │ Gateway         │─────►│ UniversalApp  │─────►│ TreeNFT        │ │
│  │                 │      │               │      │ OrnamentNFT    │ │
│  └─────────────────┘      └───────────────┘      └────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### 핵심 컨트랙트

| 컨트랙트 | 체인 | 설명 |
|----------|------|------|
| **TreeNFT** | ZetaChain | ERC721 크리스마스 트리 |
| **OrnamentNFT** | ZetaChain | ERC1155 오너먼트 |
| **UniversalApp** | ZetaChain | 크로스체인 릴레이 (Callable 인터페이스 구현) |

### 실행 방식: Base에서 크로스체인 호출

- 사용자가 **Base에서 Gateway를 통해** 호출
- **EIP-7702로 가스비 스폰서링** 가능
- UniversalApp이 메시지를 받아 TreeNFT/OrnamentNFT 호출

> ⚠️ ZetaChain 직접 호출은 사용하지 않습니다 (ZETA 가스비 문제)

### UniversalApp 인터페이스 (ZetaChain UniversalContract)

```solidity
/// @notice Provides contextual information when executing a cross-chain call on ZetaChain.
struct MessageContext {
    bytes sender;        // chain-agnostic sender (bytes로 EVM/non-EVM 모두 지원)
    address senderEVM;   // EVM 체인인 경우 sender의 address 형태
    uint256 chainID;     // 원본 체인 ID (예: 84532 = Base Sepolia)
}

abstract contract UniversalContract {
    function onCall(
        MessageContext calldata context,
        address zrc20,      // ZRC20 토큰 주소 (무자산 호출 시 address(0))
        uint256 amount,     // ZRC20 토큰 수량
        bytes calldata message
    ) external virtual;
}
```

---

## 컨트랙트 주소

### ZetaChain Mainnet (7000)

```typescript
const CONTRACTS = {
  TREE_NFT: "0x...",           // TreeNFT Proxy
  ORNAMENT_NFT: "0x...",       // OrnamentNFT Proxy
  UNIVERSAL_APP: "0x...",      // UniversalApp Proxy
  GATEWAY: "0xfEDD7A6e3Ef1cC470fbfbF955a22D793dDC0F44E",  // ZetaChain Gateway
};
```

### ZetaChain Testnet (7001)

```typescript
const CONTRACTS = {
  TREE_NFT: "0x...",           // TreeNFT Proxy
  ORNAMENT_NFT: "0x...",       // OrnamentNFT Proxy
  UNIVERSAL_APP: "0x...",      // UniversalApp Proxy
  GATEWAY: "0x6c533f7fe93fae114d0954697069df33c9b74fd7",  // ZetaChain Gateway
};
```

### Base Gateway 주소

| Network | Gateway |
|---------|---------|
| Base Mainnet (8453) | `0x48B9AACC350b20147001f88821d31731Ba4C30ed` |
| Base Sepolia (84532) | `0x0c487a766110c85d301d96e33579c5b317fa4995` |

---

## 게임 룰

### Tree NFT
- **지갑당 1개**: 백엔드에서 관리 (컨트랙트에서 강제하지 않음)
- **배경 선택**: 유저 지갑을 분석해 백엔드가 결정
- **소유권**: volr-sdk 계정이 소유, 여러 외부 지갑 연결 가능

### Ornament NFT
- **무료 뽑기**: 관리자가 등록한 오너먼트 중 백엔드가 랜덤 선택 (tokenId 0-1000)
- **커스텀 오너먼트 (관리자 전용)**: 관리자가 IPFS 등에 이미지를 업로드하고, 특정 유저에게 직접 민팅 (`adminMintCustomOrnament`) (tokenId 1001+)
- **장착 = 소각**: 오너먼트를 트리에 장착하면 **NFT가 소각(burn)**됨
- **선물 가능**: 누구나 다른 사람의 트리에 오너먼트 장착 가능
- **Display**: 트리에 표시되는 오너먼트는 최대 MAX_DISPLAY(10)개
- **Reserve**: 10개 초과 시 reserve에 저장, 언제든 display로 승격 가능

---

## Tree NFT 민팅

### 1. 서명 생성 (백엔드)

```typescript
import { ethers } from 'ethers';

// 환경변수
const SIGNER_PRIVATE_KEY = process.env.SIGNER_PRIVATE_KEY;
const TREE_NFT_ADDRESS = process.env.TREE_NFT_ADDRESS;
const CHAIN_ID = 7000; // ZetaChain Mainnet

// EIP-712 도메인
const domain = {
  name: 'ZetaTree',
  version: '1',
  chainId: CHAIN_ID,
  verifyingContract: TREE_NFT_ADDRESS,
};

// EIP-712 타입
const types = {
  MintPermit: [
    { name: 'to', type: 'address' },
    { name: 'treeId', type: 'uint256' },
    { name: 'backgroundId', type: 'uint256' },
    { name: 'uri', type: 'string' },
    { name: 'deadline', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
  ],
};

async function createTreeMintSignature(
  userAddress: string,
  treeId: bigint,
  backgroundId: bigint,
  metadataUri: string,
  nonce: bigint
): Promise<{ permit: MintPermit; signature: string }> {
  const signer = new ethers.Wallet(SIGNER_PRIVATE_KEY);
  
  // 서명 유효기간: 1시간
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
  
  const permit = {
    to: userAddress,
    treeId: treeId,
    backgroundId: backgroundId,
    uri: metadataUri,
    deadline: deadline,
    nonce: nonce,
  };
  
  const signature = await signer.signTypedData(domain, types, permit);
  
  return { permit, signature };
}
```

### 2. API 플로우

```typescript
// POST /api/tree/mint
async function handleTreeMintRequest(req: Request) {
  const { walletAddress } = req.body;
  
  // 1. 이미 트리가 있는지 확인
  const existingTree = await db.tree.findByWallet(walletAddress);
  if (existingTree) {
    throw new Error('이미 트리를 보유하고 있습니다.');
  }
  
  // 2. 지갑 분석 → 배경 결정
  const backgroundId = await analyzeWalletAndSelectBackground(walletAddress);
  
  // 3. 트리 ID 생성 (고유해야 함)
  const treeId = await generateUniqueTreeId();
  
  // 4. 메타데이터 생성 및 업로드
  const metadataUri = await createAndUploadTreeMetadata(treeId, backgroundId);
  
  // 5. 컨트랙트에서 현재 nonce 조회
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const treeContract = new ethers.Contract(TREE_NFT_ADDRESS, TREE_ABI, provider);
  const nonce = await treeContract.nonces(walletAddress);
  
  // 6. 서명 생성
  const { permit, signature } = await createTreeMintSignature(
    walletAddress,
    BigInt(treeId),
    BigInt(backgroundId),
    metadataUri,
    nonce
  );
  
  // 7. DB에 저장 (중복 사용 방지)
  await db.treeMintRequest.create({
    walletAddress,
    treeId,
    backgroundId,
    signature,
    nonce: nonce.toString(),
    status: 'pending',
  });
  
  // 8. 클라이언트에 반환
  return {
    permit,
    signature,
    contractAddress: TREE_NFT_ADDRESS,
  };
}
```

### 3. 트랜잭션 실행 (프론트엔드 - Base에서 크로스체인 호출)

> ⚠️ **중요**: `gateway.call()`은 **revert 처리를 지원하지 않습니다!**  
> - `callOnRevert`는 반드시 `false`
> - `onRevertGasLimit`는 반드시 `0`
> - revert 처리가 필요하면 `depositAndCall()` 사용

```typescript
import { ethers } from 'ethers';

const GATEWAY_ABI = [
  'function call(address receiver, bytes calldata payload, tuple(address revertAddress, bool callOnRevert, address abortAddress, bytes revertMessage, uint256 onRevertGasLimit) revertOptions) external payable',
];

async function mintTreeCrossChain(permit: MintPermit, signature: string) {
  const provider = new ethers.BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();
  
  // 1. 메시지 인코딩
  const actionType = '0x01'; // ACTION_MINT_TREE
  const payload = ethers.AbiCoder.defaultAbiCoder().encode(
    ['tuple(address to, uint256 treeId, uint256 backgroundId, string uri, uint256 deadline, uint256 nonce)', 'bytes'],
    [permit, signature]
  );
  const message = ethers.concat([actionType, payload]);
  
  // 2. Gateway 호출
  const gateway = new ethers.Contract(BASE_GATEWAY_ADDRESS, GATEWAY_ABI, signer);
  
  // ⚠️ gateway.call()에서는 revert 처리 불가!
  const revertOptions = {
    revertAddress: ethers.ZeroAddress,  // call()에서는 사용 안 됨
    callOnRevert: false,                // ⚠️ 반드시 false!
    abortAddress: ethers.ZeroAddress,   // 또는 유효한 onAbort 구현 컨트랙트
    revertMessage: '0x',
    onRevertGasLimit: 0n,               // ⚠️ 반드시 0!
  };
  
  const tx = await gateway.call(
    UNIVERSAL_APP_ADDRESS,  // ZetaChain UniversalApp 주소
    message,
    revertOptions
  );
  
  await tx.wait();
  console.log('Cross-chain tree mint initiated');
}
```

---

## Ornament NFT 무료 뽑기

### 1. 서명 생성 (백엔드)

```typescript
const ornamentDomain = {
  name: 'ZetaOrnament',
  version: '1',
  chainId: 7000,
  verifyingContract: ORNAMENT_NFT_ADDRESS,
};

const ornamentTypes = {
  OrnamentMintPermit: [
    { name: 'to', type: 'address' },
    { name: 'tokenId', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
  ],
};

async function createOrnamentMintSignature(
  userAddress: string,
  tokenId: bigint,
  nonce: bigint
): Promise<{ permit: OrnamentMintPermit; signature: string }> {
  const signer = new ethers.Wallet(SIGNER_PRIVATE_KEY);
  
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
  
  const permit = {
    to: userAddress,
    tokenId: tokenId,
    deadline: deadline,
    nonce: nonce,
  };
  
  const signature = await signer.signTypedData(ornamentDomain, ornamentTypes, permit);
  
  return { permit, signature };
}
```

### 2. 뽑기 API

```typescript
// POST /api/ornament/gacha
async function handleOrnamentGacha(req: Request) {
  const { walletAddress } = req.body;
  
  // 1. 등록된 오너먼트 중 랜덤 선택 (tokenId 0-1000)
  const registeredOrnaments = await db.ornament.findAllRegistered();
  const selectedOrnament = selectRandomOrnament(registeredOrnaments);
  
  // 2. nonce 조회
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, provider);
  const nonce = await ornamentContract.nonces(walletAddress);
  
  // 3. 서명 생성
  const { permit, signature } = await createOrnamentMintSignature(
    walletAddress,
    BigInt(selectedOrnament.tokenId),
    nonce
  );
  
  // 4. DB 저장
  await db.ornamentMintRequest.create({
    walletAddress,
    ornamentId: selectedOrnament.tokenId,
    signature,
    nonce: nonce.toString(),
    status: 'pending',
  });
  
  return {
    permit,
    signature,
    ornament: selectedOrnament,
    contractAddress: ORNAMENT_NFT_ADDRESS,
  };
}
```

### 3. 트랜잭션 실행 (프론트엔드 - Base에서 크로스체인 호출)

> ⚠️ **중요**: `gateway.call()`은 revert 처리를 지원하지 않습니다!

```typescript
async function mintOrnamentCrossChain(permit: OrnamentMintPermit, signature: string) {
  const provider = new ethers.BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();
  
  // 1. 메시지 인코딩
  const actionType = '0x02'; // ACTION_MINT_ORNAMENT_FREE
  const payload = ethers.AbiCoder.defaultAbiCoder().encode(
    ['tuple(address to, uint256 tokenId, uint256 deadline, uint256 nonce)', 'bytes'],
    [permit, signature]
  );
  const message = ethers.concat([actionType, payload]);
  
  // 2. Gateway 호출
  const gateway = new ethers.Contract(BASE_GATEWAY_ADDRESS, GATEWAY_ABI, signer);
  
  // ⚠️ gateway.call()에서는 revert 처리 불가!
  const revertOptions = {
    revertAddress: ethers.ZeroAddress,
    callOnRevert: false,                // ⚠️ 반드시 false!
    abortAddress: ethers.ZeroAddress,
    revertMessage: '0x',
    onRevertGasLimit: 0n,               // ⚠️ 반드시 0!
  };
  
  const tx = await gateway.call(UNIVERSAL_APP_ADDRESS, message, revertOptions);
  await tx.wait();
}
```

---

## Ornament NFT 커스텀 (관리자 전용)

> ⚠️ **중요 정책 변경**  
>- 이전 버전에서는 사용자가 USDC로 결제해 커스텀 오너먼트를 민팅하는 모델이었지만,  
>- **현재 버전에서는 오너먼트 커스텀 민팅은 전적으로 관리자 전용(on ZetaChain)**으로 변경되었습니다.  
>- 사용자 입장에서는 "관리자가 만들어준 커스텀 오너먼트"만 받게 됩니다 (온체인 결제 없음).

### 커스텀 오너먼트 ID 정책

- `tokenId < 1001`: 등록형(registered) 오너먼트 — 무료 뽑기/관리자 선물용
- `tokenId >= 1001`: 커스텀 오너먼트 — **관리자만 생성 가능**

### 관리자 커스텀 오너먼트 민팅 플로우

1. 관리자가 이미지 생성 후 IPFS 등 스토리지에 업로드 → `ornamentUri` 확보  
2. 온체인에서 `adminMintCustomOrnament(to, ornamentUri)` 호출  
3. 컨트랙트가 자동으로 `nextCustomTokenId`를 사용해 새 ID 발급 (1001부터 시작)

```typescript
import { ethers } from 'ethers';

async function mintAdminCustomOrnament(to: string, ornamentUri: string) {
  const adminSigner = new ethers.Wallet(ADMIN_PRIVATE_KEY, provider); // DEFAULT_ADMIN_ROLE
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, adminSigner);

  // to != 0x0 이어야 하고, 관리자만 호출 가능
  const tx = await ornamentContract.adminMintCustomOrnament(to, ornamentUri);
  await tx.wait();
}
```

### 요약

- **사용자 트랜잭션으로 커스텀 오너먼트를 직접 민팅하지 않습니다.**
- 커스텀 오너먼트는 이벤트/프로모션/운영 이슈에 따라 관리자가 수동 또는 배치로 민팅합니다.
- 백엔드는 커스텀 오너먼트 메타데이터와 수혜자 주소 목록만 관리하면 됩니다.

---

## 오너먼트 장착 (소각)

> ⚠️ **중요**: 오너먼트를 트리에 장착하면 **NFT가 소각(burn)**됩니다!

### 핵심 개념

- 오너먼트 장착 = 오너먼트 NFT 소각
- **누구나** 다른 사람의 트리에 오너먼트를 장착할 수 있음 (선물 개념)
- 장착한 사람의 오너먼트가 소각됨
- TreeNFT 컨트랙트가 OrnamentNFT의 `burnForAttachment()` 호출

### 트랜잭션 실행 (프론트엔드 - Base에서 크로스체인 호출)

```typescript
async function attachOrnamentCrossChain(
  userAddress: string,
  treeId: bigint,
  ornamentId: bigint
) {
  const provider = new ethers.BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();
  
  // 1. 메시지 인코딩
  const actionType = '0x04'; // ACTION_ADD_ORNAMENT
  const payload = ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'uint256', 'uint256'],
    [userAddress, treeId, ornamentId]
  );
  const message = ethers.concat([actionType, payload]);
  
  // 2. Gateway 호출
  const gateway = new ethers.Contract(BASE_GATEWAY_ADDRESS, GATEWAY_ABI, signer);
  
  const revertOptions = {
    revertAddress: ethers.ZeroAddress,
    callOnRevert: false,
    abortAddress: ethers.ZeroAddress,
    revertMessage: '0x',
    onRevertGasLimit: 0n,
  };
  
  const tx = await gateway.call(UNIVERSAL_APP_ADDRESS, message, revertOptions);
  await tx.wait();
  
  console.log('Cross-chain ornament attachment initiated');
}
```

### 장착 전 잔액 확인

```typescript
async function checkOrnamentBalance(userAddress: string, ornamentId: bigint) {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, provider);
  
  const balance = await ornamentContract.balanceOf(userAddress, ornamentId);
  return balance > 0n;
}
```

### 이벤트 구독 (백엔드)

```typescript
// OrnamentAttached 이벤트 구독
treeContract.on('OrnamentAttached', (treeId, ornamentId, sender, index) => {
  console.log(`Tree ${treeId}: Ornament ${ornamentId} attached by ${sender} at index ${index}`);
  // DB 업데이트 - 오너먼트가 소각되었음을 기록
});

// OrnamentBurned 이벤트 구독 (OrnamentNFT에서)
ornamentContract.on('OrnamentBurned', (from, ornamentId) => {
  console.log(`Ornament ${ornamentId} burned from ${from}`);
});
```

---

## 크로스체인 호출 (Base → ZetaChain)

### Action Types

| Action | Code | 설명 |
|--------|------|------|
| `ACTION_MINT_TREE` | `0x01` | 트리 민팅 |
| `ACTION_MINT_ORNAMENT_FREE` | `0x02` | 무료 오너먼트 민팅 |
| `ACTION_ADD_ORNAMENT` | `0x04` | 오너먼트 장착 |

### Gateway 함수

#### `call()` - 토큰 전송 없이 메시지만 전달

```solidity
function call(
    address receiver,       // UniversalApp 주소
    bytes calldata payload, // action + encoded data
    RevertOptions revertOptions
) external payable;
```

#### `depositAndCall()` - 토큰과 함께 메시지 전달

```solidity
function depositAndCall(
    address receiver,       // UniversalApp 주소
    uint256 amount,         // 전송할 토큰 수량
    address asset,          // ERC20 토큰 주소 (예: USDC)
    bytes calldata payload, // action + encoded data
    RevertOptions revertOptions
) external payable;
```

### RevertOptions 구조

```typescript
interface RevertOptions {
  revertAddress: string;    // 실패 시 환불받을 주소 (depositAndCall에서만 유효)
  callOnRevert: boolean;    // 실패 시 콜백 호출 여부
  abortAddress: string;     // 중단 시 호출할 주소 (onAbort 구현 필요)
  revertMessage: string;    // 실패 시 전달할 메시지
  onRevertGasLimit: bigint; // 실패 콜백 가스 한도 (max: 2,000,000)
}
```

> ⚠️ **gateway.call() 사용 시 제약사항:**
> - `callOnRevert`는 **반드시 `false`** (자산 없이는 revert 가스비 지불 불가)
> - `onRevertGasLimit`는 **반드시 `0`**
> - revert/환불 처리가 필요하면 `depositAndCall()` 사용
```

### UniversalApp.onCall() 동작

```solidity
// ZetaChain Gateway가 호출
function onCall(
    MessageContext calldata context,  // { sender: bytes, senderEVM: address, chainID: uint256 }
    address zrc20,                    // ZRC20 토큰 주소 (무자산 호출 시 address(0))
    uint256 amount,                   // ZRC20 토큰 수량
    bytes calldata message            // action + payload
) external onlyGateway;
```

- `context.sender`: 원본 체인에서의 발신자 주소 (bytes, chain-agnostic)
- `context.senderEVM`: EVM 체인인 경우 발신자 주소 (address)
- `context.chainID`: 원본 체인 ID (예: 84532 = Base Sepolia, 8453 = Base Mainnet)
- `zrc20`: depositAndCall로 전송된 ZRC20 토큰 주소 (call()의 경우 address(0))
- `amount`: depositAndCall로 전송된 토큰 수량 (call()의 경우 0)
- `message[0]`: action type (0x01, 0x02, 0x03, 0x04)
- `message[1:]`: action별 인코딩된 데이터

### 크로스체인 트랜잭션 상태 추적

```typescript
// ZetaChain Explorer API를 통해 CCTX 상태 확인
async function checkCCTXStatus(txHash: string) {
  const response = await fetch(
    `https://zetachain-athens.blockpi.network/lcd/v1/public/zeta-chain/crosschain/cctx/${txHash}`
  );
  const data = await response.json();
  return data.CrossChainTx.cctx_status.status;
  // "PendingOutbound" | "OutboundMined" | "Reverted"
}
```

---

## Nonce 관리

### 중요 사항

1. **nonce는 유저별로 관리**: 각 유저의 현재 nonce를 컨트랙트에서 조회
2. **TreeNFT와 OrnamentNFT는 별도 nonce**: 각 컨트랙트마다 독립적
3. **서명 생성 시 최신 nonce 사용**: 오래된 nonce로 만든 서명은 무효
4. **DB에 서명 상태 저장**: pending → confirmed 또는 expired

### Nonce 조회

```typescript
// TreeNFT nonce
const treeNonce = await treeContract.nonces(userAddress);

// OrnamentNFT nonce
const ornamentNonce = await ornamentContract.nonces(userAddress);
```

### 동시 요청 처리

```typescript
async function handleMintRequest(walletAddress: string) {
  // 락 획득
  const lock = await acquireLock(`mint:${walletAddress}`);
  
  try {
    const nonce = await contract.nonces(walletAddress);
    
    // 이미 해당 nonce로 생성된 pending 서명이 있는지 확인
    const existingRequest = await db.mintRequest.findOne({
      walletAddress,
      nonce: nonce.toString(),
      status: 'pending',
    });
    
    if (existingRequest) {
      return existingRequest;
    }
    
    // 새 서명 생성
    const { permit, signature } = await createSignature(walletAddress, nonce);
    await db.mintRequest.create({ ... });
    
    return { permit, signature };
  } finally {
    await releaseLock(lock);
  }
}
```

---

## 관리자 기능

### 배경 배치 등록

```typescript
async function registerBackgrounds(backgrounds: { id: bigint; uri: string }[]) {
  const adminSigner = new ethers.Wallet(ADMIN_PRIVATE_KEY, provider);
  const treeContract = new ethers.Contract(TREE_NFT_ADDRESS, TREE_ABI, adminSigner);
  
  const backgroundIds = backgrounds.map(b => b.id);
  const uris = backgrounds.map(b => b.uri);
  
  const tx = await treeContract.registerBackgrounds(backgroundIds, uris);
  await tx.wait();
}
```

### 오너먼트 배치 등록

```typescript
async function registerOrnaments(ornaments: { id: bigint; uri: string }[]) {
  const adminSigner = new ethers.Wallet(ADMIN_PRIVATE_KEY, provider);
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, adminSigner);
  
  // tokenId는 CUSTOM_TOKEN_START(1001) 미만이어야 함
  for (const o of ornaments) {
    if (o.id >= 1001n) {
      throw new Error(`Invalid tokenId: ${o.id}. Must be less than 1001`);
    }
  }
  
  const tokenIds = ornaments.map(o => o.id);
  const uris = ornaments.map(o => o.uri);
  
  const tx = await ornamentContract.registerOrnaments(tokenIds, uris);
  await tx.wait();
}
```

### 관리자 선물 민팅 (등록된 오너먼트 지급)

관리자는 이미 등록된 오너먼트(`ornamentRegistered[tokenId] == true`)를 **원하는 유저 지갑으로 무료로 선물**할 수 있습니다.

```typescript
async function giftRegisteredOrnament(to: string, tokenId: bigint) {
  const adminSigner = new ethers.Wallet(ADMIN_PRIVATE_KEY, provider);
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, adminSigner);

  // to != 0x0, tokenId는 등록된 ID여야 함
  const tx = await ornamentContract.adminMintOrnament(to, tokenId);
  await tx.wait();
}
```

- 결제 없이 1개씩 민팅 (ERC1155 수량 1)
- `to == address(0)`인 경우 `InvalidAddress`로 revert
- 등록되지 않은 `tokenId`인 경우 `OrnamentNotRegistered`로 revert

### OrnamentNFT ↔ TreeNFT 연결 설정

```typescript
// OrnamentNFT에 TreeNFT 주소 설정 (burnForAttachment 호출 권한)
const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, adminSigner);
await (await ornamentContract.setTreeNFT(TREE_NFT_ADDRESS)).wait();

// TreeNFT에 OrnamentNFT 주소 설정
const treeContract = new ethers.Contract(TREE_NFT_ADDRESS, TREE_ABI, adminSigner);
await (await treeContract.setOrnamentNFT(ORNAMENT_NFT_ADDRESS)).wait();
```

### 결제 토큰 및 수수료 설정

```typescript
// 결제 토큰 설정 (예: USDC)
await ornamentContract.setPaymentToken(USDC_ADDRESS);

// 민팅 수수료 설정 (예: 10 USDC = 10000000, 6 decimals)
await ornamentContract.setMintFee(10000000n);
```

### 수수료 인출

```typescript
async function withdrawFees(treasuryAddress: string) {
  const adminSigner = new ethers.Wallet(ADMIN_PRIVATE_KEY, provider);
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, adminSigner);
  
  const tx = await ornamentContract.withdrawFees(treasuryAddress);
  await tx.wait();
}
```

### UniversalApp 설정

```typescript
const universalApp = new ethers.Contract(UNIVERSAL_APP_ADDRESS, UNIVERSAL_APP_ABI, adminSigner);

// NFT 컨트랙트 주소 설정
await (await universalApp.setTreeNFT(TREE_NFT_ADDRESS)).wait();
await (await universalApp.setOrnamentNFT(ORNAMENT_NFT_ADDRESS)).wait();

// USDC ZRC20 주소 설정 (ZetaChain에서의 브릿지된 USDC)
await (await universalApp.setUsdcZRC20(USDC_ZRC20_ADDRESS)).wait();

// 커스텀 오너먼트 가격 설정 (6 decimals)
await (await universalApp.setCustomOrnamentPrice(10000000n)).wait();

// Fee Receiver 설정
await (await universalApp.setFeeReceiver(FEE_RECEIVER_ADDRESS)).wait();

// Gateway 주소 설정
await (await universalApp.setGateway(GATEWAY_ADDRESS)).wait();
```

---

## 에러 핸들링

### TreeNFT 에러

| 에러 | 설명 | 대응 |
|------|------|------|
| `InvalidSignature` | 서명이 유효하지 않음 | 서명 재생성 |
| `ExpiredDeadline` | 서명 만료 | 새 서명 요청 |
| `InvalidNonce` | nonce 불일치 | 최신 nonce로 재시도 |
| `BackgroundNotRegistered` | 미등록 배경 | 관리자가 배경 등록 필요 |
| `BackgroundAlreadyRegistered` | 이미 등록된 배경 | 다른 ID 사용 |
| `NotTreeOwner` | 트리 소유자 아님 | 소유권 확인 |
| `NotUniversalApp` | UniversalApp이 아닌 주소에서 호출 | 크로스체인만 사용 |
| `InvalidAddress` | Zero address | 올바른 주소 사용 |

### OrnamentNFT 에러

| 에러 | 설명 | 대응 |
|------|------|------|
| `InvalidSignature` | 서명이 유효하지 않음 | 서명 재생성 |
| `ExpiredDeadline` | 서명 만료 | 새 서명 요청 |
| `InvalidNonce` | nonce 불일치 | 최신 nonce로 재시도 |
| `OrnamentNotRegistered` | 미등록 오너먼트 | 관리자가 오너먼트 등록 필요 |
| `OrnamentAlreadyRegistered` | 이미 등록된 오너먼트 | 다른 ID 사용 |
| `InvalidTokenId` | 커스텀 범위(≥1001) ID로 등록 시도 | 1000 이하의 ID 사용 |
| `NotTreeNFT` | TreeNFT가 아닌 주소에서 burn 호출 | TreeNFT에서만 호출 가능 |
| `InvalidAddress` | Zero address | 올바른 주소 사용 |

### UniversalApp 에러

| 에러 | 설명 | 대응 |
|------|------|------|
| `OnlyGateway` | Gateway가 아닌 주소에서 호출 | Gateway를 통해서만 호출 |
| `InvalidAction` | 잘못된 action type | 올바른 action code 사용 (0x01, 0x02, 0x04) |
| `InvalidAddress` | Zero address | 올바른 주소 사용 |

---

## 체크리스트

### 배포 후 설정

- [ ] 배경 배치 등록 (`TreeNFT.registerBackgrounds`)
- [ ] 오너먼트 배치 등록 (`OrnamentNFT.registerOrnaments`)
- [ ] OrnamentNFT에 TreeNFT 주소 설정 (`OrnamentNFT.setTreeNFT`)
- [ ] TreeNFT에 OrnamentNFT 주소 설정 (`TreeNFT.setOrnamentNFT`)
- [ ] TreeNFT에 UniversalApp 주소 설정 (`TreeNFT.setUniversalApp`)
- [ ] UniversalApp에 TreeNFT 주소 설정 (`UniversalApp.setTreeNFT`)
- [ ] UniversalApp에 OrnamentNFT 주소 설정 (`UniversalApp.setOrnamentNFT`)
- [ ] UniversalApp에 Gateway 주소 설정 (`UniversalApp.setGateway`)
- [ ] Signer 주소 확인

### 테스트 (모두 크로스체인)

- [ ] Tree 민팅
- [ ] 무료 오너먼트 민팅
- [ ] 오너먼트 장착 (소각 확인)
- [ ] 선물 기능 (다른 사람 트리에 장착)
- [ ] CCTX 상태 확인 (성공/실패)
