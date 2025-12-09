// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreeNFT} from "../src/TreeNFT.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TreeNFTTest is Test {
    TreeNFT public tree;
    OrnamentNFT public ornament;

    address public admin = address(1);
    address public signerWallet;
    uint256 public signerPrivateKey;
    address public user = address(3);
    address public user2 = address(4);

    uint256 constant TREE_ID = 1;
    uint256 constant BACKGROUND_ID = 100;
    string constant BACKGROUND_URI = "ipfs://background/100";
    string constant TREE_URI = "ipfs://tree/1";

    bytes32 private constant MINT_PERMIT_TYPEHASH = keccak256(
        "MintPermit(address to,uint256 treeId,uint256 backgroundId,string uri,uint256 deadline,uint256 nonce)"
    );

    bytes32 private constant ORNAMENT_MINT_PERMIT_TYPEHASH =
        keccak256("OrnamentMintPermit(address to,uint256 tokenId,uint256 deadline,uint256 nonce)");

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

        // Register background
        uint256[] memory bgIds = new uint256[](1);
        bgIds[0] = BACKGROUND_ID;
        string[] memory bgUris = new string[](1);
        bgUris[0] = BACKGROUND_URI;
        tree.registerBackgrounds(bgIds, bgUris);

        // Link TreeNFT <-> OrnamentNFT
        tree.setOrnamentNFT(address(ornament));
        ornament.setTreeNFT(address(tree));

        // Register ornaments (1-20)
        uint256[] memory ornIds = new uint256[](20);
        string[] memory ornUris = new string[](20);
        for (uint256 i = 0; i < 20; i++) {
            ornIds[i] = i + 1;
            ornUris[i] = "";
        }
        ornament.registerOrnaments(ornIds, ornUris);

        vm.stopPrank();
    }

    function _createSignature(
        address to,
        uint256 treeId,
        uint256 backgroundId,
        string memory uri,
        uint256 deadline,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(MINT_PERMIT_TYPEHASH, to, treeId, backgroundId, keccak256(bytes(uri)), deadline, nonce)
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", tree.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    // ============ Scenario 1: 유효한 서명으로 민팅 성공 + 배경 저장 확인 ============
    function testMintWithValidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(user);

        bytes memory signature = _createSignature(user, TREE_ID, BACKGROUND_ID, TREE_URI, deadline, nonce);

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user, treeId: TREE_ID, backgroundId: BACKGROUND_ID, uri: TREE_URI, deadline: deadline, nonce: nonce
        });

        vm.prank(user);
        tree.mintWithSignature(permit, signature);

        assertEq(tree.ownerOf(TREE_ID), user);
        assertEq(tree.tokenURI(TREE_ID), TREE_URI);
        assertEq(tree.treeBackground(TREE_ID), BACKGROUND_ID);
        assertEq(tree.nonces(user), 1);
    }

    // ============ Scenario 2: 만료된 서명 거부 ============
    function testRevertOnExpiredSignature() public {
        uint256 deadline = block.timestamp - 1; // Already expired
        uint256 nonce = tree.nonces(user);

        bytes memory signature = _createSignature(user, TREE_ID, BACKGROUND_ID, TREE_URI, deadline, nonce);

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user, treeId: TREE_ID, backgroundId: BACKGROUND_ID, uri: TREE_URI, deadline: deadline, nonce: nonce
        });

        vm.prank(user);
        vm.expectRevert(TreeNFT.ExpiredDeadline.selector);
        tree.mintWithSignature(permit, signature);
    }

    // ============ Scenario 3: 잘못된 서명 거부 ============
    function testRevertOnInvalidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(user);

        // Sign with wrong private key
        uint256 wrongPrivateKey = 0xBAD;
        bytes32 structHash = keccak256(
            abi.encode(MINT_PERMIT_TYPEHASH, user, TREE_ID, BACKGROUND_ID, keccak256(bytes(TREE_URI)), deadline, nonce)
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", tree.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, hash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user, treeId: TREE_ID, backgroundId: BACKGROUND_ID, uri: TREE_URI, deadline: deadline, nonce: nonce
        });

        vm.prank(user);
        vm.expectRevert(TreeNFT.InvalidSignature.selector);
        tree.mintWithSignature(permit, wrongSignature);
    }

    // ============ Scenario 4: nonce 재사용 방지 ============
    function testRevertOnNonceReuse() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(user);

        bytes memory signature = _createSignature(user, TREE_ID, BACKGROUND_ID, TREE_URI, deadline, nonce);

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user, treeId: TREE_ID, backgroundId: BACKGROUND_ID, uri: TREE_URI, deadline: deadline, nonce: nonce
        });

        vm.prank(user);
        tree.mintWithSignature(permit, signature);

        // Try to reuse the same signature
        TreeNFT.MintPermit memory permit2 = TreeNFT.MintPermit({
            to: user,
            treeId: 2,
            backgroundId: BACKGROUND_ID,
            uri: "ipfs://tree/2",
            deadline: deadline,
            nonce: nonce // Same nonce
        });

        vm.prank(user);
        vm.expectRevert(TreeNFT.InvalidNonce.selector);
        tree.mintWithSignature(permit2, signature);
    }

    // ============ Scenario 5: 등록되지 않은 배경 ID 사용 시 실패 ============
    function testRevertOnUnregisteredBackground() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(user);
        uint256 unregisteredBgId = 999;

        bytes memory signature = _createSignature(user, TREE_ID, unregisteredBgId, TREE_URI, deadline, nonce);

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user, treeId: TREE_ID, backgroundId: unregisteredBgId, uri: TREE_URI, deadline: deadline, nonce: nonce
        });

        vm.prank(user);
        vm.expectRevert(TreeNFT.BackgroundNotRegistered.selector);
        tree.mintWithSignature(permit, signature);
    }

    // ============ Scenario 6: 오너먼트 장착 (display + reserve) ============
    function testAddOrnamentsToTree() public {
        // Mint tree first
        _mintTreeForUser(user, TREE_ID);

        // Add 15 ornaments
        for (uint256 i = 1; i <= 15; i++) {
            _mintAndAttachOrnament(user, TREE_ID, i);
        }

        uint256[] memory allOrnaments = tree.getTreeOrnaments(TREE_ID);
        assertEq(allOrnaments.length, 15);

        uint256[] memory displayOrnaments = tree.getDisplayOrnaments(TREE_ID);
        assertEq(displayOrnaments.length, 10);
        assertEq(displayOrnaments[0], 1);
        assertEq(displayOrnaments[9], 10);

        // Check ornaments are burned (not transferred to contract)
        assertEq(ornament.balanceOf(address(tree), 1), 0);
        assertEq(ornament.balanceOf(user, 1), 0);
    }

    // ============ Scenario 7: Display 순서 변경 ============
    function testSetDisplayOrder() public {
        _mintTreeForUser(user, TREE_ID);

        // Add 12 ornaments (using IDs 1-12)
        for (uint256 i = 1; i <= 12; i++) {
            _mintAndAttachOrnament(user, TREE_ID, i);
        }

        // Reorder display: reverse first 10
        uint256[] memory newOrder = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            newOrder[i] = 9 - i;
        }
        vm.prank(user);
        tree.setDisplayOrder(TREE_ID, newOrder);

        uint256[] memory display = tree.getDisplayOrnaments(TREE_ID);
        assertEq(display[0], 10); // Was at index 9
        assertEq(display[9], 1); // Was at index 0
    }

    // ============ Scenario 8: Reserve → Display 배치 승격 ============
    function testPromoteOrnaments() public {
        _mintTreeForUser(user, TREE_ID);

        // Add 12 ornaments (IDs 1-12)
        for (uint256 i = 1; i <= 12; i++) {
            _mintAndAttachOrnament(user, TREE_ID, i);
        }

        // Promote ornament at index 10 (ID 11) to index 0, and index 11 (ID 12) to index 1
        uint256[] memory displayIdxs = new uint256[](2);
        displayIdxs[0] = 0;
        displayIdxs[1] = 1;

        uint256[] memory reserveIdxs = new uint256[](2);
        reserveIdxs[0] = 10;
        reserveIdxs[1] = 11;

        vm.prank(user);
        tree.promoteOrnaments(TREE_ID, displayIdxs, reserveIdxs);

        uint256[] memory display = tree.getDisplayOrnaments(TREE_ID);
        assertEq(display[0], 11); // Promoted from reserve
        assertEq(display[1], 12); // Promoted from reserve
    }

    // ============ Scenario 9: 트리 소유자가 아닌 사람이 오너먼트 추가 시도 ============
    function testAddOrnamentToOthersTree() public {
        // user owns the tree, user2 gifts an ornament to user's tree
        _mintTreeForUser(user, TREE_ID);
        _mintOrnamentForUser(user2, 1);

        vm.startPrank(user2);
        ornament.setApprovalForAll(address(tree), true);
        tree.addOrnamentToTree(TREE_ID, 1);
        vm.stopPrank();

        // Verify ornament was added to user's tree
        uint256[] memory ornaments = tree.getTreeOrnaments(TREE_ID);
        assertEq(ornaments.length, 1);
        assertEq(ornaments[0], 1);
    }

    // ============ Admin Functions ============
    function testAdminCanUpdateSigner() public {
        address newSigner = address(100);

        vm.prank(admin);
        tree.setSigner(newSigner);

        assertEq(tree.signer(), newSigner);
    }

    function testAdminCanUpdateBackgroundUri() public {
        string memory newUri = "ipfs://background/100-v2";

        vm.prank(admin);
        tree.updateBackgroundUri(BACKGROUND_ID, newUri);

        assertEq(tree.backgroundUri(BACKGROUND_ID), newUri);
    }

    function testRevertRegisterDuplicateBackground() public {
        uint256[] memory bgIds = new uint256[](1);
        bgIds[0] = BACKGROUND_ID;
        string[] memory uris = new string[](1);
        uris[0] = "ipfs://dup";

        vm.prank(admin);
        vm.expectRevert(TreeNFT.BackgroundAlreadyRegistered.selector);
        tree.registerBackgrounds(bgIds, uris);
    }

    // ============ Batch Registration ============
    function testBatchRegisterBackgrounds() public {
        uint256[] memory bgIds = new uint256[](3);
        bgIds[0] = 200;
        bgIds[1] = 201;
        bgIds[2] = 202;

        string[] memory uris = new string[](3);
        uris[0] = "ipfs://background/200";
        uris[1] = "ipfs://background/201";
        uris[2] = "ipfs://background/202";

        vm.prank(admin);
        tree.registerBackgrounds(bgIds, uris);

        assertTrue(tree.backgroundRegistered(200));
        assertTrue(tree.backgroundRegistered(201));
        assertTrue(tree.backgroundRegistered(202));
        assertEq(tree.backgroundUri(200), "ipfs://background/200");
        assertEq(tree.backgroundUri(201), "ipfs://background/201");
        assertEq(tree.backgroundUri(202), "ipfs://background/202");
    }

    function testRevertBatchRegisterWithMismatchedArrays() public {
        uint256[] memory bgIds = new uint256[](2);
        bgIds[0] = 300;
        bgIds[1] = 301;

        string[] memory uris = new string[](3);
        uris[0] = "ipfs://a";
        uris[1] = "ipfs://b";
        uris[2] = "ipfs://c";

        vm.prank(admin);
        vm.expectRevert(TreeNFT.ArrayLengthMismatch.selector);
        tree.registerBackgrounds(bgIds, uris);
    }

    function testRevertBatchRegisterWithDuplicateInBatch() public {
        uint256[] memory bgIds = new uint256[](2);
        bgIds[0] = 400;
        bgIds[1] = 400; // Duplicate

        string[] memory uris = new string[](2);
        uris[0] = "ipfs://a";
        uris[1] = "ipfs://b";

        vm.prank(admin);
        vm.expectRevert(TreeNFT.BackgroundAlreadyRegistered.selector);
        tree.registerBackgrounds(bgIds, uris);
    }

    // ============ Scenario 10: getTreeOrnaments 배열 반환 테스트 ============
    function testGetTreeOrnamentsEmpty() public {
        _mintTreeForUser(user, TREE_ID);

        uint256[] memory orn = tree.getTreeOrnaments(TREE_ID);
        assertEq(orn.length, 0);
    }

    function testGetTreeOrnamentsSingleItem() public {
        _mintTreeForUser(user, TREE_ID);
        _mintAndAttachOrnament(user, TREE_ID, 1);

        uint256[] memory orn = tree.getTreeOrnaments(TREE_ID);
        assertEq(orn.length, 1);
        assertEq(orn[0], 1);
    }

    function testGetTreeOrnamentsMultipleItems() public {
        _mintTreeForUser(user, TREE_ID);

        for (uint256 i = 1; i <= 5; i++) {
            _mintAndAttachOrnament(user, TREE_ID, i);
        }

        uint256[] memory orn = tree.getTreeOrnaments(TREE_ID);
        assertEq(orn.length, 5);
        assertEq(orn[0], 1);
        assertEq(orn[1], 2);
        assertEq(orn[2], 3);
        assertEq(orn[3], 4);
        assertEq(orn[4], 5);
    }

    function testGetTreeOrnamentsIndependentBetweenTrees() public {
        uint256 treeId2 = 2;
        _mintTreeForUser(user, TREE_ID);
        _mintTreeForUser(user2, treeId2);

        // user의 트리에 오너먼트 추가
        _mintAndAttachOrnament(user, TREE_ID, 1);
        _mintAndAttachOrnament(user, TREE_ID, 2);

        // user2의 트리에 오너먼트 추가
        _mintAndAttachOrnament(user2, treeId2, 3);

        // 각 트리의 오너먼트가 독립적으로 관리되는지 확인
        uint256[] memory ornamentsTree1 = tree.getTreeOrnaments(TREE_ID);
        uint256[] memory ornamentsTree2 = tree.getTreeOrnaments(treeId2);

        assertEq(ornamentsTree1.length, 2);
        assertEq(ornamentsTree1[0], 1);
        assertEq(ornamentsTree1[1], 2);

        assertEq(ornamentsTree2.length, 1);
        assertEq(ornamentsTree2[0], 3);
    }

    function testGetTreeOrnamentsAfterPromote() public {
        _mintTreeForUser(user, TREE_ID);

        // 12개 오너먼트 추가
        for (uint256 i = 1; i <= 12; i++) {
            _mintAndAttachOrnament(user, TREE_ID, i);
        }

        // 프로모트 전 확인
        uint256[] memory before = tree.getTreeOrnaments(TREE_ID);
        assertEq(before.length, 12);
        assertEq(before[0], 1);
        assertEq(before[10], 11);

        // reserve에서 display로 프로모트 (index 10 <-> index 0)
        uint256[] memory displayIdxs = new uint256[](1);
        displayIdxs[0] = 0;
        uint256[] memory reserveIdxs = new uint256[](1);
        reserveIdxs[0] = 10;
        vm.prank(user);
        tree.promoteOrnaments(TREE_ID, displayIdxs, reserveIdxs);

        // 프로모트 후 확인 (스왑되어야 함)
        uint256[] memory after_ = tree.getTreeOrnaments(TREE_ID);
        assertEq(after_.length, 12);
        assertEq(after_[0], 11); // 11이 첫 번째로 이동
        assertEq(after_[10], 1); // 1이 reserve로 이동
    }

    // ============ Helper ============
    function _mintTreeForUser(address to, uint256 treeId) internal {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(to);

        bytes memory signature = _createSignature(to, treeId, BACKGROUND_ID, TREE_URI, deadline, nonce);

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: to, treeId: treeId, backgroundId: BACKGROUND_ID, uri: TREE_URI, deadline: deadline, nonce: nonce
        });

        vm.prank(to);
        tree.mintWithSignature(permit, signature);
    }

    function _createOrnamentSignature(address to, uint256 tokenId, uint256 deadline, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(ORNAMENT_MINT_PERMIT_TYPEHASH, to, tokenId, deadline, nonce));
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", ornament.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _mintOrnamentForUser(address to, uint256 ornamentId) internal {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = ornament.nonces(to);

        bytes memory signature = _createOrnamentSignature(to, ornamentId, deadline, nonce);

        OrnamentNFT.OrnamentMintPermit memory permit =
            OrnamentNFT.OrnamentMintPermit({to: to, tokenId: ornamentId, deadline: deadline, nonce: nonce});

        vm.prank(to);
        ornament.mintWithSignature(permit, signature);
    }

    function _mintAndAttachOrnament(address to, uint256 treeId, uint256 ornamentId) internal {
        _mintOrnamentForUser(to, ornamentId);

        vm.startPrank(to);
        ornament.setApprovalForAll(address(tree), true);
        tree.addOrnamentToTree(treeId, ornamentId);
        vm.stopPrank();
    }
}
