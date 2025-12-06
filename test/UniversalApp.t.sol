// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreeNFT} from "../src/TreeNFT.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";
import {UniversalApp} from "../src/UniversalApp.sol";
import {MessageContext, UniversalContract} from "../src/interfaces/zetachain/UniversalContract.sol";
import {RevertContext} from "../src/interfaces/zetachain/Revertable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ITreeNFT} from "../src/interfaces/ITreeNFT.sol";
import {IOrnamentNFT} from "../src/interfaces/IOrnamentNFT.sol";

contract UniversalAppTest is Test {
    TreeNFT public tree;
    OrnamentNFT public ornament;
    UniversalApp public universalApp;

    address public admin = address(1);
    address public gateway = address(2);
    address public signerWallet;
    uint256 public signerPrivateKey;
    address public user = address(4);
    address public feeReceiver = address(5);

    address public mockUsdcZRC20 = address(100);
    uint256 public customOrnamentPrice = 10 * 1e6; // 10 USDC

    uint256 constant TREE_ID = 1;
    uint256 constant BACKGROUND_ID = 100;
    string constant TREE_URI = "ipfs://tree/1";

    bytes32 private constant MINT_PERMIT_TYPEHASH = keccak256(
        "MintPermit(address to,uint256 treeId,uint256 backgroundId,string uri,uint256 deadline,uint256 nonce)"
    );

    bytes32 private constant ORNAMENT_MINT_PERMIT_TYPEHASH = keccak256(
        "OrnamentMintPermit(address to,uint256 tokenId,uint256 deadline,uint256 nonce)"
    );

    function setUp() public {
        signerPrivateKey = 0xA11CE;
        signerWallet = vm.addr(signerPrivateKey);

        vm.startPrank(admin);

        // Deploy TreeNFT
        TreeNFT treeImpl = new TreeNFT();
        bytes memory treeInitData = abi.encodeCall(TreeNFT.initialize, (signerWallet));
        ERC1967Proxy treeProxy = new ERC1967Proxy(address(treeImpl), treeInitData);
        tree = TreeNFT(address(treeProxy));

        // Deploy OrnamentNFT
        OrnamentNFT ornamentImpl = new OrnamentNFT();
        bytes memory ornamentInitData = abi.encodeCall(OrnamentNFT.initialize, (signerWallet, ""));
        ERC1967Proxy ornamentProxy = new ERC1967Proxy(address(ornamentImpl), ornamentInitData);
        ornament = OrnamentNFT(address(ornamentProxy));

        // Deploy UniversalApp
        UniversalApp universalAppImpl = new UniversalApp();
        bytes memory universalAppInitData = abi.encodeCall(UniversalApp.initialize, (gateway));
        ERC1967Proxy universalAppProxy = new ERC1967Proxy(address(universalAppImpl), universalAppInitData);
        universalApp = UniversalApp(payable(address(universalAppProxy)));

        // Link contracts
        tree.setOrnamentNFT(address(ornament));
        ornament.setTreeNFT(address(tree));
        universalApp.setTreeNFT(address(tree));
        universalApp.setOrnamentNFT(address(ornament));
        universalApp.setFeeReceiver(feeReceiver);
        universalApp.setUsdcZRC20(mockUsdcZRC20);
        universalApp.setCustomOrnamentPrice(customOrnamentPrice);

        // Register background
        uint256[] memory bgIds = new uint256[](1);
        bgIds[0] = BACKGROUND_ID;
        string[] memory bgUris = new string[](1);
        bgUris[0] = "ipfs://bg/100";
        tree.registerBackgrounds(bgIds, bgUris);

        // Register ornaments
        uint256[] memory ornIds = new uint256[](10);
        string[] memory ornUris = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            ornIds[i] = i + 1;
            ornUris[i] = "";
        }
        ornament.registerOrnaments(ornIds, ornUris);

        vm.stopPrank();
    }

    // ============ onlyGateway Tests ============

    function testOnlyGatewayCanCallOnCall() public {
        MessageContext memory ctx = MessageContext({
            sender: abi.encodePacked(user),
            senderEVM: user,
            chainID: 84532 // Base Sepolia
        });

        bytes memory message = abi.encodePacked(universalApp.ACTION_MINT_TREE());

        // Non-gateway should revert
        vm.prank(user);
        vm.expectRevert(UniversalContract.OnlyGateway.selector);
        universalApp.onCall(ctx, address(0), 0, message);
    }

    function testGatewayCanCallOnCall() public {
        // Create valid permit and signature
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = tree.nonces(user);

        TreeNFT.MintPermit memory permit = TreeNFT.MintPermit({
            to: user,
            treeId: TREE_ID,
            backgroundId: BACKGROUND_ID,
            uri: TREE_URI,
            deadline: deadline,
            nonce: nonce
        });

        bytes memory signature = _createTreeSignature(permit);

        bytes memory message = abi.encodePacked(
            universalApp.ACTION_MINT_TREE(),
            abi.encode(permit, signature)
        );

        MessageContext memory ctx = MessageContext({
            sender: abi.encodePacked(user),
            senderEVM: user,
            chainID: 84532 // Base Sepolia
        });

        vm.prank(gateway);
        universalApp.onCall(ctx, address(0), 0, message);

        // Verify tree was minted
        assertEq(tree.ownerOf(TREE_ID), user);
    }

    // ============ Invalid Action Tests ============

    function testRevertOnInvalidAction() public {
        MessageContext memory ctx = MessageContext({
            sender: abi.encodePacked(user),
            senderEVM: user,
            chainID: 84532 // Base Sepolia
        });

        bytes memory message = abi.encodePacked(bytes1(0xFF)); // Invalid action

        vm.prank(gateway);
        vm.expectRevert(UniversalApp.InvalidAction.selector);
        universalApp.onCall(ctx, address(0), 0, message);
    }

    // ============ Admin Function Tests ============

    function testAdminCanSetContracts() public {
        address newTree = address(200);
        address newOrnament = address(201);

        vm.startPrank(admin);
        universalApp.setTreeNFT(newTree);
        universalApp.setOrnamentNFT(newOrnament);
        vm.stopPrank();

        assertEq(universalApp.treeNFT(), newTree);
        assertEq(universalApp.ornamentNFT(), newOrnament);
    }

    function testAdminCanSetPricing() public {
        uint256 newPrice = 20 * 1e6;

        vm.prank(admin);
        universalApp.setCustomOrnamentPrice(newPrice);

        assertEq(universalApp.customOrnamentPrice(), newPrice);
    }

    function testNonAdminCannotSetContracts() public {
        vm.prank(user);
        vm.expectRevert();
        universalApp.setTreeNFT(address(200));
    }

    // ============ Zero Address Validation Tests ============

    function testRevertOnZeroAddressTreeNFT() public {
        vm.prank(admin);
        vm.expectRevert(UniversalApp.InvalidAddress.selector);
        universalApp.setTreeNFT(address(0));
    }

    function testRevertOnZeroAddressOrnamentNFT() public {
        vm.prank(admin);
        vm.expectRevert(UniversalApp.InvalidAddress.selector);
        universalApp.setOrnamentNFT(address(0));
    }

    function testRevertOnZeroAddressFeeReceiver() public {
        vm.prank(admin);
        vm.expectRevert(UniversalApp.InvalidAddress.selector);
        universalApp.setFeeReceiver(address(0));
    }

    function testRevertOnZeroAddressGateway() public {
        vm.prank(admin);
        vm.expectRevert(UniversalApp.InvalidAddress.selector);
        universalApp.setGateway(address(0));
    }

    // ============ Free Ornament Minting Tests ============

    function testMintOrnamentFreeCrossChain() public {
        uint256 ornamentId = 1;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = ornament.nonces(user);

        OrnamentNFT.OrnamentMintPermit memory permit = OrnamentNFT.OrnamentMintPermit({
            to: user,
            tokenId: ornamentId,
            deadline: deadline,
            nonce: nonce
        });

        bytes memory signature = _createOrnamentSignature(permit);

        bytes memory message = abi.encodePacked(
            universalApp.ACTION_MINT_ORNAMENT_FREE(),
            abi.encode(permit, signature)
        );

        MessageContext memory ctx = MessageContext({
            sender: abi.encodePacked(user),
            senderEVM: user,
            chainID: 84532 // Base Sepolia
        });

        vm.prank(gateway);
        universalApp.onCall(ctx, address(0), 0, message);

        // Verify ornament was minted
        assertEq(ornament.balanceOf(user, ornamentId), 1);
    }

    // ============ Helper Functions ============

    function _createTreeSignature(TreeNFT.MintPermit memory permit) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                MINT_PERMIT_TYPEHASH,
                permit.to,
                permit.treeId,
                permit.backgroundId,
                keccak256(bytes(permit.uri)),
                permit.deadline,
                permit.nonce
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", tree.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _createOrnamentSignature(OrnamentNFT.OrnamentMintPermit memory permit) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                ORNAMENT_MINT_PERMIT_TYPEHASH,
                permit.to,
                permit.tokenId,
                permit.deadline,
                permit.nonce
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", ornament.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }
}
