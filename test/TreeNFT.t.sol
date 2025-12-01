// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreeNFT} from "../src/TreeNFT.sol";

contract TreeNFTTest is Test {
    TreeNFT public tree;

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

    function setUp() public {
        // Generate signer wallet
        signerPrivateKey = 0xA11CE;
        signerWallet = vm.addr(signerPrivateKey);

        vm.startPrank(admin);
        tree = new TreeNFT(signerWallet);

        // Register background
        tree.registerBackground(BACKGROUND_ID, BACKGROUND_URI);
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

    // ============ Scenario 1: 유효한 서명으로 민팅 성공 + 배경 저장 확인 ============
    function testMintWithValidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(user);

        bytes memory signature = _createSignature(
            user, TREE_ID, BACKGROUND_ID, TREE_URI, deadline, nonce
        );

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user,
            treeId: TREE_ID,
            backgroundId: BACKGROUND_ID,
            uri: TREE_URI,
            deadline: deadline,
            nonce: nonce
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

        bytes memory signature = _createSignature(
            user, TREE_ID, BACKGROUND_ID, TREE_URI, deadline, nonce
        );

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user,
            treeId: TREE_ID,
            backgroundId: BACKGROUND_ID,
            uri: TREE_URI,
            deadline: deadline,
            nonce: nonce
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
            abi.encode(
                MINT_PERMIT_TYPEHASH,
                user, TREE_ID, BACKGROUND_ID,
                keccak256(bytes(TREE_URI)),
                deadline, nonce
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", tree.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, hash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user,
            treeId: TREE_ID,
            backgroundId: BACKGROUND_ID,
            uri: TREE_URI,
            deadline: deadline,
            nonce: nonce
        });

        vm.prank(user);
        vm.expectRevert(TreeNFT.InvalidSignature.selector);
        tree.mintWithSignature(permit, wrongSignature);
    }

    // ============ Scenario 4: nonce 재사용 방지 ============
    function testRevertOnNonceReuse() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(user);

        bytes memory signature = _createSignature(
            user, TREE_ID, BACKGROUND_ID, TREE_URI, deadline, nonce
        );

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user,
            treeId: TREE_ID,
            backgroundId: BACKGROUND_ID,
            uri: TREE_URI,
            deadline: deadline,
            nonce: nonce
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

        bytes memory signature = _createSignature(
            user, TREE_ID, unregisteredBgId, TREE_URI, deadline, nonce
        );

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user,
            treeId: TREE_ID,
            backgroundId: unregisteredBgId,
            uri: TREE_URI,
            deadline: deadline,
            nonce: nonce
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
        vm.startPrank(user);
        for (uint256 i = 1; i <= 15; i++) {
            tree.addOrnamentToTree(TREE_ID, i);
        }
        vm.stopPrank();

        uint256[] memory allOrnaments = tree.getTreeOrnaments(TREE_ID);
        assertEq(allOrnaments.length, 15);

        uint256[] memory displayOrnaments = tree.getDisplayOrnaments(TREE_ID);
        assertEq(displayOrnaments.length, 10);
        assertEq(displayOrnaments[0], 1);
        assertEq(displayOrnaments[9], 10);
    }

    // ============ Scenario 7: Display 순서 변경 ============
    function testSetDisplayOrder() public {
        _mintTreeForUser(user, TREE_ID);

        // Add 12 ornaments
        vm.startPrank(user);
        for (uint256 i = 1; i <= 12; i++) {
            tree.addOrnamentToTree(TREE_ID, i * 10); // 10, 20, 30...
        }

        // Reorder display: reverse first 10
        uint256[] memory newOrder = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            newOrder[i] = 9 - i;
        }
        tree.setDisplayOrder(TREE_ID, newOrder);
        vm.stopPrank();

        uint256[] memory display = tree.getDisplayOrnaments(TREE_ID);
        assertEq(display[0], 100); // Was at index 9
        assertEq(display[9], 10);  // Was at index 0
    }

    // ============ Scenario 8: Reserve → Display 배치 승격 ============
    function testPromoteOrnaments() public {
        _mintTreeForUser(user, TREE_ID);

        // Add 12 ornaments
        vm.startPrank(user);
        for (uint256 i = 1; i <= 12; i++) {
            tree.addOrnamentToTree(TREE_ID, i * 10);
        }

        // Promote ornament at index 10 (110) to index 0, and index 11 (120) to index 1
        uint256[] memory displayIdxs = new uint256[](2);
        displayIdxs[0] = 0;
        displayIdxs[1] = 1;

        uint256[] memory reserveIdxs = new uint256[](2);
        reserveIdxs[0] = 10;
        reserveIdxs[1] = 11;

        tree.promoteOrnaments(TREE_ID, displayIdxs, reserveIdxs);
        vm.stopPrank();

        uint256[] memory display = tree.getDisplayOrnaments(TREE_ID);
        assertEq(display[0], 110); // Promoted from reserve
        assertEq(display[1], 120); // Promoted from reserve
    }

    // ============ Scenario 9: 트리 소유자가 아닌 사람이 오너먼트 추가 시도 ============
    function testRevertAddOrnamentNotOwner() public {
        _mintTreeForUser(user, TREE_ID);

        vm.prank(user2);
        vm.expectRevert(TreeNFT.NotTreeOwner.selector);
        tree.addOrnamentToTree(TREE_ID, 100);
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
        vm.prank(admin);
        vm.expectRevert(TreeNFT.BackgroundAlreadyRegistered.selector);
        tree.registerBackground(BACKGROUND_ID, "ipfs://dup");
    }

    // ============ Helper ============
    function _mintTreeForUser(address to, uint256 treeId) internal {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(to);

        bytes memory signature = _createSignature(
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
}
