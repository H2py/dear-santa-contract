// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ITreeNFT
 * @notice Interface for TreeNFT contract
 */
interface ITreeNFT {
    struct MintPermit {
        address to;
        uint256 treeId;
        uint256 backgroundId;
        string uri;
        uint256 deadline;
        uint256 nonce;
    }

    function mintWithSignature(MintPermit calldata permit, bytes calldata signature) external;
    function addOrnamentToTree(uint256 treeId, uint256 ornamentId) external;
    function addOrnamentToTreeFor(address user, uint256 treeId, uint256 ornamentId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function getTreeOrnaments(uint256 treeId) external view returns (uint256[] memory);
    function getDisplayOrnaments(uint256 treeId) external view returns (uint256[] memory);
    function getBackground(uint256 treeId) external view returns (uint256);
    function nonces(address user) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

