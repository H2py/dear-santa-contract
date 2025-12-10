// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOrnamentNFT
 * @notice Interface for OrnamentNFT contract
 */
interface IOrnamentNFT {
    struct OrnamentMintPermit {
        address to;
        uint256 tokenId;
        uint256 deadline;
        uint256 nonce;
    }

    function mintWithSignature(OrnamentMintPermit calldata permit, bytes calldata signature) external;
    function adminMintOrnament(address to, uint256 tokenId) external;
    function adminMintCustomOrnament(address to, string calldata ornamentUri) external;
    function burnForAttachment(address from, uint256 ornamentId) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function nonces(address user) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

