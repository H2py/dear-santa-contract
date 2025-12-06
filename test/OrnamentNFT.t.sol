// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreeNFT} from "../src/TreeNFT.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract OrnamentNFTTest is Test {
    TreeNFT public tree;
    OrnamentNFT public ornament;
    MockERC20 public paymentToken;

    address public admin = address(1);
    address public signerWallet;
    uint256 public signerPrivateKey;
    address public user = address(3);
    address public user2 = address(4);

    uint256 constant TREE_ID = 1;
    uint256 constant BACKGROUND_ID = 100;
    uint256 constant ORNAMENT_ID = 1;
    uint256 constant MINT_FEE = 100 * 10**18;
    string constant BACKGROUND_URI = "ipfs://background/100";
    string constant TREE_URI = "ipfs://tree/1";
    string constant ORNAMENT_URI = "ipfs://ornament/1";

    bytes32 private constant MINT_PERMIT_TYPEHASH = keccak256(
        "MintPermit(address to,uint256 treeId,uint256 backgroundId,string uri,uint256 deadline,uint256 nonce)"
    );

    bytes32 private constant ORNAMENT_MINT_PERMIT_TYPEHASH = keccak256(
        "OrnamentMintPermit(address to,uint256 tokenId,uint256 deadline,uint256 nonce)"
    );

    function setUp() public {
        // Generate signer wallet
        signerPrivateKey = 0xA11CE;
        signerWallet = vm.addr(signerPrivateKey);

        vm.startPrank(admin);

        // Deploy TreeNFT with proxy
        TreeNFT treeImpl = new TreeNFT();
        bytes memory treeInitData = abi.encodeCall(TreeNFT.initialize, (signerWallet));
        ERC1967Proxy treeProxy = new ERC1967Proxy(address(treeImpl), treeInitData);
        tree = TreeNFT(address(treeProxy));

        // Deploy OrnamentNFT with proxy
        OrnamentNFT ornamentImpl = new OrnamentNFT();
        bytes memory ornamentInitData = abi.encodeCall(OrnamentNFT.initialize, (signerWallet, ""));
        ERC1967Proxy ornamentProxy = new ERC1967Proxy(address(ornamentImpl), ornamentInitData);
        ornament = OrnamentNFT(address(ornamentProxy));

        paymentToken = new MockERC20();

        // Setup TreeNFT
        uint256[] memory bgIds = new uint256[](1);
        bgIds[0] = BACKGROUND_ID;
        string[] memory bgUris = new string[](1);
        bgUris[0] = BACKGROUND_URI;
        tree.registerBackgrounds(bgIds, bgUris);
        tree.setOrnamentNFT(address(ornament));

        // Setup OrnamentNFT
        uint256[] memory ornIds = new uint256[](1);
        ornIds[0] = ORNAMENT_ID;
        string[] memory ornUris = new string[](1);
        ornUris[0] = ORNAMENT_URI;
        ornament.registerOrnaments(ornIds, ornUris);
        ornament.setPaymentToken(address(paymentToken));
        ornament.setMintFee(MINT_FEE);

        vm.stopPrank();

        // Mint tree for user
        _mintTreeForUser(user, TREE_ID);

        // Give user some tokens
        paymentToken.mint(user, 1000 * 10**18);
    }

    function _createTreeSignature(
        address to,
        uint256 treeId,
        uint256 backgroundId,
        string memory uri,
        uint256 deadline,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                MINT_PERMIT_TYPEHASH,
                to,
                treeId,
                backgroundId,
                keccak256(bytes(uri)),
                deadline,
                nonce
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", tree.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _createOrnamentSignature(
        address to,
        uint256 tokenId,
        uint256 deadline,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                ORNAMENT_MINT_PERMIT_TYPEHASH,
                to,
                tokenId,
                deadline,
                nonce
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", ornament.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _mintTreeForUser(address to, uint256 treeId) internal {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(to);

        bytes memory signature = _createTreeSignature(
            to, treeId, BACKGROUND_ID, TREE_URI, deadline, nonce
        );

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: to,
            treeId: treeId,
            backgroundId: BACKGROUND_ID,
            uri: TREE_URI,
            deadline: deadline,
            nonce: nonce
        });

        vm.prank(to);
        tree.mintWithSignature(permit, signature);
    }

    // ============ Scenario 1: 무료 뽑기 - 등록된 오너먼트 서명 민팅 성공 ============
    function testMintOrnamentWithValidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = ornament.nonces(user);

        bytes memory signature = _createOrnamentSignature(
            user, ORNAMENT_ID, deadline, nonce
        );

        OrnamentNFT.OrnamentMintPermit memory permit = OrnamentNFT.OrnamentMintPermit({
            to: user,
            tokenId: ORNAMENT_ID,
            deadline: deadline,
            nonce: nonce
        });

        vm.prank(user);
        ornament.mintWithSignature(permit, signature);

        assertEq(ornament.balanceOf(user, ORNAMENT_ID), 1);
        assertEq(ornament.nonces(user), 1);
    }

    // ============ Scenario 2: 무료 뽑기 - 미등록 오너먼트 민팅 실패 ============
    function testRevertMintUnregisteredOrnament() public {
        uint256 unregisteredId = 999;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = ornament.nonces(user);

        bytes memory signature = _createOrnamentSignature(
            user, unregisteredId, deadline, nonce
        );

        OrnamentNFT.OrnamentMintPermit memory permit = OrnamentNFT.OrnamentMintPermit({
            to: user,
            tokenId: unregisteredId,
            deadline: deadline,
            nonce: nonce
        });

        vm.prank(user);
        vm.expectRevert(OrnamentNFT.OrnamentNotRegistered.selector);
        ornament.mintWithSignature(permit, signature);
    }

    // ============ Scenario 3: 유료 커스텀 - ERC20 결제 후 민팅 성공 ============
    function testMintCustomOrnamentWithPayment() public {
        string memory customUri = "ipfs://custom/1";

        vm.startPrank(user);
        paymentToken.approve(address(ornament), MINT_FEE);
        ornament.mintCustomOrnament(customUri);
        vm.stopPrank();

        // Check custom ornament ID starts from 1001
        uint256 customTokenId = ornament.CUSTOM_TOKEN_START();
        assertEq(ornament.balanceOf(user, customTokenId), 1);
        assertEq(ornament.uri(customTokenId), customUri);

        // Check payment was collected
        assertEq(paymentToken.balanceOf(address(ornament)), MINT_FEE);
        assertEq(paymentToken.balanceOf(user), 1000 * 10**18 - MINT_FEE);

        // Check next custom token ID incremented
        assertEq(ornament.nextCustomTokenId(), customTokenId + 1);
    }

    // ============ Scenario 4: 유료 커스텀 - 잔액/allowance 부족 시 실패 ============
    function testRevertMintCustomWithInsufficientBalance() public {
        vm.startPrank(user2); // user2 has no tokens
        paymentToken.approve(address(ornament), MINT_FEE);

        vm.expectRevert(); // ERC20 transfer will fail
        ornament.mintCustomOrnament("ipfs://custom/fail");
        vm.stopPrank();
    }

    function testRevertMintCustomWithoutApproval() public {
        vm.prank(user);
        vm.expectRevert(); // No approval
        ornament.mintCustomOrnament("ipfs://custom/fail");
    }

    // ============ Scenario 5: 관리자 URI 변경 기능 ============
    function testAdminCanUpdateOrnamentUri() public {
        string memory newUri = "ipfs://ornament/1-v2";

        vm.prank(admin);
        ornament.setOrnamentUri(ORNAMENT_ID, newUri);

        assertEq(ornament.uri(ORNAMENT_ID), newUri);
    }

    // ============ 추가 테스트 ============

    function testRevertMintOrnamentExpiredSignature() public {
        uint256 deadline = block.timestamp - 1; // Expired
        uint256 nonce = ornament.nonces(user);

        bytes memory signature = _createOrnamentSignature(
            user, ORNAMENT_ID, deadline, nonce
        );

        OrnamentNFT.OrnamentMintPermit memory permit = OrnamentNFT.OrnamentMintPermit({
            to: user,
            tokenId: ORNAMENT_ID,
            deadline: deadline,
            nonce: nonce
        });

        vm.prank(user);
        vm.expectRevert(OrnamentNFT.ExpiredDeadline.selector);
        ornament.mintWithSignature(permit, signature);
    }

    function testRevertMintOrnamentInvalidNonce() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 wrongNonce = 999;

        bytes memory signature = _createOrnamentSignature(
            user, ORNAMENT_ID, deadline, wrongNonce
        );

        OrnamentNFT.OrnamentMintPermit memory permit = OrnamentNFT.OrnamentMintPermit({
            to: user,
            tokenId: ORNAMENT_ID,
            deadline: deadline,
            nonce: wrongNonce
        });

        vm.prank(user);
        vm.expectRevert(OrnamentNFT.InvalidNonce.selector);
        ornament.mintWithSignature(permit, signature);
    }

    function testAdminCanWithdrawFees() public {
        // First, have user mint a custom ornament
        vm.startPrank(user);
        paymentToken.approve(address(ornament), MINT_FEE);
        ornament.mintCustomOrnament("ipfs://custom/1");
        vm.stopPrank();

        // Withdraw fees
        address treasury = address(100);
        vm.prank(admin);
        ornament.withdrawFees(treasury);

        assertEq(paymentToken.balanceOf(treasury), MINT_FEE);
        assertEq(paymentToken.balanceOf(address(ornament)), 0);
    }

    function testAdminCanUpdatePaymentSettings() public {
        address newToken = address(200);
        uint256 newFee = 50 * 10**18;

        vm.startPrank(admin);
        ornament.setPaymentToken(newToken);
        ornament.setMintFee(newFee);
        vm.stopPrank();

        assertEq(address(ornament.paymentToken()), newToken);
        assertEq(ornament.mintFee(), newFee);
    }

    function testRevertRegisterOrnamentWithCustomId() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1001; // Custom range starts at 1001
        string[] memory uris = new string[](1);
        uris[0] = "ipfs://invalid";

        vm.prank(admin);
        vm.expectRevert(OrnamentNFT.InvalidTokenId.selector);
        ornament.registerOrnaments(tokenIds, uris);
    }

    function testRevertRegisterDuplicateOrnament() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = ORNAMENT_ID;
        string[] memory uris = new string[](1);
        uris[0] = "ipfs://dup";

        vm.prank(admin);
        vm.expectRevert(OrnamentNFT.OrnamentAlreadyRegistered.selector);
        ornament.registerOrnaments(tokenIds, uris);
    }

    function testRevertMintCustomWithoutPaymentTokenSet() public {
        // Deploy new ornament with proxy without payment settings
        vm.startPrank(admin);
        OrnamentNFT newOrnamentImpl = new OrnamentNFT();
        bytes memory initData = abi.encodeCall(OrnamentNFT.initialize, (signerWallet, ""));
        ERC1967Proxy proxy = new ERC1967Proxy(address(newOrnamentImpl), initData);
        OrnamentNFT newOrnament = OrnamentNFT(address(proxy));
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(OrnamentNFT.PaymentTokenNotSet.selector);
        newOrnament.mintCustomOrnament("ipfs://fail");
    }

    // ============ Batch Registration ============
    function testBatchRegisterOrnaments() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 10;
        tokenIds[1] = 11;
        tokenIds[2] = 12;

        string[] memory uris = new string[](3);
        uris[0] = "ipfs://ornament/10";
        uris[1] = "ipfs://ornament/11";
        uris[2] = "ipfs://ornament/12";

        vm.prank(admin);
        ornament.registerOrnaments(tokenIds, uris);

        assertTrue(ornament.ornamentRegistered(10));
        assertTrue(ornament.ornamentRegistered(11));
        assertTrue(ornament.ornamentRegistered(12));
        assertEq(ornament.uri(10), "ipfs://ornament/10");
        assertEq(ornament.uri(11), "ipfs://ornament/11");
        assertEq(ornament.uri(12), "ipfs://ornament/12");
    }

    function testRevertBatchRegisterWithMismatchedArrays() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 20;
        tokenIds[1] = 21;

        string[] memory uris = new string[](3);
        uris[0] = "ipfs://a";
        uris[1] = "ipfs://b";
        uris[2] = "ipfs://c";

        vm.prank(admin);
        vm.expectRevert(OrnamentNFT.ArrayLengthMismatch.selector);
        ornament.registerOrnaments(tokenIds, uris);
    }

    function testRevertBatchRegisterWithCustomTokenId() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 30;
        tokenIds[1] = 1001; // Custom range (invalid)

        string[] memory uris = new string[](2);
        uris[0] = "ipfs://a";
        uris[1] = "ipfs://b";

        vm.prank(admin);
        vm.expectRevert(OrnamentNFT.InvalidTokenId.selector);
        ornament.registerOrnaments(tokenIds, uris);
    }

    function testRevertBatchRegisterWithDuplicateInBatch() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 40;
        tokenIds[1] = 40; // Duplicate

        string[] memory uris = new string[](2);
        uris[0] = "ipfs://a";
        uris[1] = "ipfs://b";

        vm.prank(admin);
        vm.expectRevert(OrnamentNFT.OrnamentAlreadyRegistered.selector);
        ornament.registerOrnaments(tokenIds, uris);
    }

    // ============ Admin Gift Mint ============

    function testAdminCanGiftRegisteredOrnament() public {
        vm.prank(admin);
        ornament.adminMintOrnament(user2, ORNAMENT_ID);

        assertEq(ornament.balanceOf(user2, ORNAMENT_ID), 1);
    }

    function testRevertAdminGiftToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(OrnamentNFT.InvalidAddress.selector);
        ornament.adminMintOrnament(address(0), ORNAMENT_ID);
    }

    function testRevertAdminGiftUnregisteredOrnament() public {
        uint256 unregisteredId = 999;

        vm.prank(admin);
        vm.expectRevert(OrnamentNFT.OrnamentNotRegistered.selector);
        ornament.adminMintOrnament(user2, unregisteredId);
    }
}
