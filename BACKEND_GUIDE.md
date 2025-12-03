# Dear Santa 백엔드 가이드라인

이 문서는 Dear Santa 서비스의 백엔드에서 스마트 컨트랙트와 상호작용하는 방법을 설명합니다.

## 목차

1. [개요](#개요)
2. [컨트랙트 구조](#컨트랙트-구조)
3. [게임 룰](#게임-룰)
4. [Tree NFT 민팅](#tree-nft-민팅)
5. [Ornament NFT 무료 뽑기](#ornament-nft-무료-뽑기)
6. [Ornament NFT 유료 커스텀](#ornament-nft-유료-커스텀)
7. [오너먼트 장착](#오너먼트-장착)
8. [Nonce 관리](#nonce-관리)
9. [관리자 기능](#관리자-기능)
10. [에러 핸들링](#에러-핸들링)

---

## 개요

Dear Santa는 크리스마스 트리와 오너먼트를 NFT로 발행하는 서비스입니다.

- **TreeNFT (ERC721)**: 각 유저의 크리스마스 트리
- **OrnamentNFT (ERC1155)**: 트리에 장식하는 오너먼트

### 핵심 플로우

1. **오너먼트 민팅**: 서명 기반으로 오너먼트 NFT를 유저 지갑에 발행
2. **오너먼트 장착**: 유저가 자신의 오너먼트를 트리에 장착 (NFT가 트리 컨트랙트로 전송됨)

---

## 컨트랙트 구조

### TreeNFT

```typescript
interface TreeNFT {
  // 서명 기반 민팅
  mintWithSignature(permit: MintPermit, signature: bytes): void;
  
  // 오너먼트 관리 (유저가 approve 후 호출, NFT가 트리 컨트랙트로 전송됨)
  addOrnamentToTree(treeId: uint256, ornamentId: uint256): void;
  setDisplayOrder(treeId: uint256, newOrder: uint256[]): void;
  promoteOrnaments(treeId: uint256, displayIdxs: uint256[], reserveIdxs: uint256[]): void;
  
  // 조회
  getTreeOrnaments(treeId: uint256): uint256[];
  getDisplayOrnaments(treeId: uint256): uint256[];
  getBackground(treeId: uint256): uint256;
  nonces(address): uint256;
  treeBackground(treeId: uint256): uint256;
  backgroundUri(backgroundId: uint256): string;
  backgroundRegistered(backgroundId: uint256): boolean;
  registeredBackgroundCount(): uint256;

  // 관리자 전용
  registerBackgrounds(backgroundIds: uint256[], uris: string[]): void;
  updateBackgroundUri(backgroundId: uint256, uri: string): void;
  setSigner(signer: address): void;
  setOrnamentNFT(ornamentNFT: address): void;

  // 이벤트
  event TreeMinted(uint256 indexed treeId, address indexed to, uint256 backgroundId);
  event OrnamentAdded(uint256 indexed treeId, uint256 indexed ornamentId, address indexed sender, uint256 index);
  event DisplayOrderUpdated(uint256 indexed treeId);
  event OrnamentsPromoted(uint256 indexed treeId);
}

struct MintPermit {
  to: address;          // 수신자 주소
  treeId: uint256;      // 트리 ID
  backgroundId: uint256; // 배경 ID
  uri: string;          // 메타데이터 URI
  deadline: uint256;    // 만료 시간 (unix timestamp)
  nonce: uint256;       // replay 방지용
}
```

### OrnamentNFT

```typescript
interface OrnamentNFT {
  // 무료 뽑기 (서명 기반) - 유저 지갑에 민팅만 함
  mintWithSignature(permit: OrnamentMintPermit, signature: bytes): void;
  
  // 유료 커스텀 - 유저 지갑에 민팅만 함
  mintCustomOrnament(uri: string): void;
  
  // 조회
  nonces(address): uint256;
  ornamentRegistered(tokenId: uint256): boolean;
  registeredOrnamentCount(): uint256;
  mintFee(): uint256;
  nextCustomTokenId(): uint256;
  CUSTOM_TOKEN_START(): uint256;  // 1001

  // 관리자 전용
  registerOrnaments(tokenIds: uint256[], uris: string[]): void;
  setOrnamentUri(tokenId: uint256, uri: string): void;
  setSigner(signer: address): void;
  setPaymentToken(token: address): void;
  setMintFee(fee: uint256): void;
  withdrawFees(to: address): void;

  // 이벤트
  event OrnamentMinted(uint256 indexed tokenId, address indexed to);
  event OrnamentRegistered(uint256 indexed tokenId, string uri);
  event OrnamentUriUpdated(uint256 indexed tokenId, string uri);
}

struct OrnamentMintPermit {
  to: address;        // 수신자 주소
  tokenId: uint256;   // 오너먼트 ID (등록된 것만)
  deadline: uint256;  // 만료 시간
  nonce: uint256;     // replay 방지용
}
```

---

## 게임 룰

### Tree NFT
- **지갑당 1개**: 백엔드에서 관리 (컨트랙트에서 강제하지 않음)
- **배경 선택**: 유저 지갑을 분석해 백엔드가 결정
- **소유권**: volr-sdk 계정이 소유, 여러 외부 지갑 연결 가능

### Ornament NFT
- **무료 뽑기**: 관리자가 등록한 오너먼트 중 백엔드가 랜덤 선택
- **유료 커스텀**: ERC20 토큰으로 결제 후 원하는 이미지 업로드
- **장착**: 오너먼트 민팅 후 유저가 별도로 트리에 장착 (NFT가 트리 컨트랙트로 전송됨)
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
const CHAIN_ID = parseInt(process.env.CHAIN_ID);

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
): Promise<{ permit: any; signature: string }> {
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

### 3. 프론트엔드에서 트랜잭션 실행

```typescript
// 유저가 서명을 받은 후 직접 민팅
async function mintTree(permit: MintPermit, signature: string) {
  const treeContract = new ethers.Contract(
    TREE_NFT_ADDRESS,
    TREE_ABI,
    signer // 유저의 signer
  );
  
  const tx = await treeContract.mintWithSignature(permit, signature);
  await tx.wait();
}
```

---

## Ornament NFT 무료 뽑기

### 1. 서명 생성 (백엔드)

```typescript
const ornamentDomain = {
  name: 'ZetaOrnament',
  version: '1',
  chainId: CHAIN_ID,
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
): Promise<{ permit: any; signature: string }> {
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
  
  // 1. 등록된 오너먼트 중 랜덤 선택
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

---

## Ornament NFT 유료 커스텀

유료 커스텀은 서명이 필요 없습니다. 유저가 직접 ERC20 approve 후 민팅합니다.

### 프론트엔드 플로우

```typescript
async function mintCustomOrnament(
  imageUri: string,
  paymentTokenAddress: string
) {
  const provider = new ethers.BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();
  
  // 1. 결제 토큰 approve
  const paymentToken = new ethers.Contract(paymentTokenAddress, ERC20_ABI, signer);
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, signer);
  
  const mintFee = await ornamentContract.mintFee();
  const approveTx = await paymentToken.approve(ORNAMENT_NFT_ADDRESS, mintFee);
  await approveTx.wait();
  
  // 2. 커스텀 오너먼트 민팅
  const mintTx = await ornamentContract.mintCustomOrnament(imageUri);
  const receipt = await mintTx.wait();
  
  // 3. 이벤트에서 새로 생성된 tokenId 추출
  const mintEvent = receipt.logs.find(
    (log) => log.topics[0] === ethers.id('OrnamentMinted(uint256,address)')
  );
  // tokenId는 1001부터 시작
}
```

---

## 오너먼트 장착

오너먼트를 트리에 장착하면 **NFT가 유저 지갑에서 TreeNFT 컨트랙트로 전송**됩니다.

### 프론트엔드 플로우

```typescript
async function attachOrnamentToTree(
  treeId: bigint,
  ornamentId: bigint
) {
  const provider = new ethers.BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();
  
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, signer);
  const treeContract = new ethers.Contract(TREE_NFT_ADDRESS, TREE_ABI, signer);
  
  // 1. TreeNFT 컨트랙트에 오너먼트 전송 권한 부여
  const isApproved = await ornamentContract.isApprovedForAll(signer.address, TREE_NFT_ADDRESS);
  if (!isApproved) {
    const approveTx = await ornamentContract.setApprovalForAll(TREE_NFT_ADDRESS, true);
    await approveTx.wait();
  }
  
  // 2. 오너먼트 장착 (NFT가 트리 컨트랙트로 전송됨)
  const attachTx = await treeContract.addOrnamentToTree(treeId, ornamentId);
  await attachTx.wait();
}
```

### 백엔드 이벤트 구독

```typescript
// OrnamentAdded 이벤트 구독으로 장착 추적
treeContract.on('OrnamentAdded', (treeId, ornamentId, sender) => {
  console.log(`Tree ${treeId}: Ornament ${ornamentId} added by ${sender}`);
  // DB 업데이트
});
```

---

## Nonce 관리

### 중요 사항

1. **nonce는 유저별로 관리**: 각 유저의 현재 nonce를 컨트랙트에서 조회
2. **서명 생성 시 최신 nonce 사용**: 오래된 nonce로 만든 서명은 무효
3. **DB에 서명 상태 저장**: pending → confirmed 또는 expired

### 동시 요청 처리

```typescript
// 동일 유저의 동시 요청 방지
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
      // 기존 서명 반환
      return existingRequest;
    }
    
    // 새 서명 생성
    const { permit, signature } = await createSignature(walletAddress, nonce);
    
    // DB 저장
    await db.mintRequest.create({ ... });
    
    return { permit, signature };
  } finally {
    await releaseLock(lock);
  }
}
```

### 서명 만료 처리

```typescript
// 주기적으로 실행되는 크론잡
async function cleanupExpiredSignatures() {
  const now = Math.floor(Date.now() / 1000);
  
  await db.mintRequest.updateMany(
    {
      status: 'pending',
      deadline: { $lt: now },
    },
    {
      status: 'expired',
    }
  );
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

### 부적절한 오너먼트 처리

```typescript
async function hideInappropriateOrnament(tokenId: bigint) {
  const adminSigner = new ethers.Wallet(ADMIN_PRIVATE_KEY, provider);
  const ornamentContract = new ethers.Contract(ORNAMENT_NFT_ADDRESS, ORNAMENT_ABI, adminSigner);
  
  const tx = await ornamentContract.setOrnamentUri(tokenId, 'ipfs://placeholder/hidden');
  await tx.wait();
}
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

---

## 에러 핸들링

### 컨트랙트 에러 코드

| 에러 | 설명 | 대응 |
|------|------|------|
| `InvalidSignature` | 서명이 유효하지 않음 | 서명 재생성 |
| `ExpiredDeadline` | 서명 만료 | 새 서명 요청 |
| `InvalidNonce` | nonce 불일치 | 최신 nonce로 재시도 |
| `BackgroundNotRegistered` | 미등록 배경 | 관리자가 배경 등록 필요 |
| `BackgroundAlreadyRegistered` | 이미 등록된 배경 | 다른 ID 사용 |
| `OrnamentNotRegistered` | 미등록 오너먼트 | 관리자가 오너먼트 등록 필요 |
| `OrnamentAlreadyRegistered` | 이미 등록된 오너먼트 | 다른 ID 사용 |
| `InvalidTokenId` | 커스텀 범위(≥1001) ID로 등록 시도 | 1000 이하의 ID 사용 |
| `NotTreeOwner` | 트리 소유자 아님 | 소유권 확인 |
| `PaymentTokenNotSet` | 결제 토큰 미설정 | 관리자 설정 필요 |
| `MintFeeNotSet` | 민팅 비용 미설정 | 관리자 설정 필요 |
| `ArrayLengthMismatch` | 배열 길이 불일치 | 배열 길이 확인 |


---

## 체크리스트

배포 전 확인사항:

- [ ] 배경 배치 등록 완료 (`registerBackgrounds`)
- [ ] 오너먼트 배치 등록 완료 (`registerOrnaments`)
- [ ] OrnamentNFT 주소를 TreeNFT에 설정 (`setOrnamentNFT`)
- [ ] 결제 토큰 설정 (`setPaymentToken`)
- [ ] 민팅 비용 설정 (`setMintFee`)
- [ ] Signer 주소 확인
