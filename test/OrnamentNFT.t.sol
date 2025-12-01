// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";

contract OrnamentNFTTest is Test {
    OrnamentNFT private ornament;
    address private minter = address(1);
    address private user = address(2);
    address private other = address(3);

    uint256 private constant CANDY = 101;
    uint256 private constant GIFT = 201;

    function setUp() public {
        // baseUri는 여기서는 비워두고, uri 직접 세팅하는 흐름만 사용
        ornament = new OrnamentNFT("");
        // DEFAULT_ADMIN_ROLE = 이 테스트 컨트랙트 (deployer)
        ornament.grantRole(ornament.MINTER_ROLE(), minter);
    }

    // ============ AccessControl 관련 ============

    function testDefaultAdminIsDeployer() public {
        assertTrue(ornament.hasRole(ornament.DEFAULT_ADMIN_ROLE(), address(this)), "deployer should be default admin");
    }

    function testRevokeMinterRolePreventsMint() public {
        // minter 역할 제거
        ornament.revokeRole(ornament.MINTER_ROLE(), minter);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, minter, ornament.MINTER_ROLE()
            )
        );
        vm.prank(minter);
        ornament.mintOrnament(user, CANDY, 1, "ipfs://candy");
    }

    // ============ mintOrnament 관련 ============

    function testMintAssignsBalanceAndUri() public {
        vm.prank(minter);
        ornament.mintOrnament(user, CANDY, 3, "ipfs://candy");

        assertEq(ornament.balanceOf(user, CANDY), 3);
        assertEq(ornament.totalSupply(CANDY), 3);
        assertEq(ornament.uri(CANDY), "ipfs://candy");
    }

    function testMintSameTokenUriOverwriteReverts() public {
        vm.startPrank(minter);
        ornament.mintOrnament(user, CANDY, 1, "ipfs://candy-v1");
        vm.expectRevert(abi.encodeWithSelector(OrnamentNFT.UriAlreadySet.selector, CANDY));
        ornament.mintOrnament(user, CANDY, 1, "ipfs://candy-v2");
        vm.stopPrank();

        assertEq(ornament.balanceOf(user, CANDY), 1);
        assertEq(ornament.uri(CANDY), "ipfs://candy-v1"); // 기존 URI 유지
    }

    function testMintSameTokenKeepsUriWhenEmptyUriPassed() public {
        vm.startPrank(minter);
        ornament.mintOrnament(user, CANDY, 1, "ipfs://candy");
        ornament.mintOrnament(user, CANDY, 2, ""); // 빈 uri → 기존 값 유지 의도
        vm.stopPrank();

        assertEq(ornament.balanceOf(user, CANDY), 3);
        assertEq(ornament.uri(CANDY), "ipfs://candy");
    }

    function testOnlyMinterCanMint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, ornament.MINTER_ROLE()
            )
        );
        vm.prank(user);
        ornament.mintOrnament(user, CANDY, 1, "ipfs://unauthorized");
    }

    // ============ mintBatchOrnaments 관련 ============

    function testMintBatchSetsUris() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = CANDY;
        ids[1] = GIFT;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5;
        amounts[1] = 7;

        string[] memory uris = new string[](2);
        uris[0] = "ipfs://candy";
        uris[1] = "ipfs://gift";

        vm.prank(minter);
        ornament.mintBatchOrnaments(user, ids, amounts, uris);

        assertEq(ornament.balanceOf(user, CANDY), 5);
        assertEq(ornament.balanceOf(user, GIFT), 7);
        assertEq(ornament.uri(CANDY), "ipfs://candy");
        assertEq(ornament.uri(GIFT), "ipfs://gift");
    }

    function testMintBatchWithoutUrisWorks() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = CANDY;
        ids[1] = GIFT;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5;
        amounts[1] = 7;

        // uris 비어있어도 민트는 정상 동작해야 함
        string[] memory uris = new string[](0);

        vm.prank(minter);
        ornament.mintBatchOrnaments(user, ids, amounts, uris);

        assertEq(ornament.balanceOf(user, CANDY), 5);
        assertEq(ornament.balanceOf(user, GIFT), 7);
    }

    function testMintBatchUriLengthMismatchReverts() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = CANDY;
        ids[1] = GIFT;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5;
        amounts[1] = 7;

        // ids는 2개, uris는 1개 → revert 예상
        string[] memory uris = new string[](1);
        uris[0] = "ipfs://only-one";

        vm.startPrank(minter);
        vm.expectRevert(OrnamentNFT.ArrayLengthMismatch.selector);
        ornament.mintBatchOrnaments(user, ids, amounts, uris);
        vm.stopPrank();
    }

    function testMintBatchDuplicateIdsReverts() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = CANDY;
        ids[1] = CANDY;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        string[] memory uris = new string[](2);
        uris[0] = "ipfs://candy-1";
        uris[1] = "ipfs://candy-2";

        vm.expectRevert(OrnamentNFT.ArrayLengthMismatch.selector);
        vm.prank(minter);
        ornament.mintBatchOrnaments(user, ids, amounts, uris);
    }

    // ============ 전송 & Supply 관련 ============

    function testTransferUpdatesBalancesNotTotalSupply() public {
        vm.prank(minter);
        ornament.mintOrnament(user, CANDY, 3, "ipfs://candy");

        uint256 beforeSupply = ornament.totalSupply(CANDY);

        vm.prank(user);
        ornament.safeTransferFrom(user, minter, CANDY, 1, "");

        assertEq(ornament.totalSupply(CANDY), beforeSupply);
        assertEq(ornament.balanceOf(user, CANDY), 2);
        assertEq(ornament.balanceOf(minter, CANDY), 1);
    }

    // ============ supportsInterface ============

    function testSupportsInterface() public {
        // ERC1155 인터페이스 지원 여부
        assertTrue(ornament.supportsInterface(type(IERC1155).interfaceId));
        // AccessControl 인터페이스 지원 여부
        assertTrue(ornament.supportsInterface(type(IAccessControl).interfaceId));
    }
}
