// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TreeNFT} from "../src/TreeNFT.sol";

contract TreeNFTTest is Test {
    TreeNFT private tree;
    address private minter = address(1);
    address private user = address(2);

    function setUp() public {
        tree = new TreeNFT();
        tree.grantRole(tree.MINTER_ROLE(), minter);
    }

    function testMintAssignsOwnerAndUri() public {
        vm.prank(minter);
        uint256 tokenId = tree.mintTree(user, "tree-1", "ipfs://tree-1");

        assertEq(tokenId, 1);
        assertEq(tree.totalSupply(), 1);
        assertEq(tree.ownerOf(tokenId), user);
        assertEq(tree.tokenURI(tokenId), "ipfs://tree-1");
        assertEq(tree.treeIdToTokenId("tree-1"), tokenId);
    }

    function testMintRevertsOnDuplicateTreeId() public {
        vm.prank(minter);
        tree.mintTree(user, "tree-dup", "ipfs://a");

        vm.prank(minter);
        vm.expectRevert(bytes("Tree already minted"));
        tree.mintTree(user, "tree-dup", "ipfs://b");
    }

    function testOnlyMinterCanMint() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, tree.MINTER_ROLE())
        );
        vm.prank(user);
        tree.mintTree(user, "tree-unauthorized", "ipfs://unauthorized");
    }
}
