// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";

/// @title Ornament1155
/// @notice ERC1155 버전 오너먼트, 17개 타입 등의 동일 아이템을 대량 발행/전송하기 위한 용도.
contract OrnamentNFT is ERC1155, ERC1155Supply, ERC1155URIStorage, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    mapping(uint256 => bool) private _uriSet;

    error UriAlreadySet(uint256 tokenId);
    error ArrayLengthMismatch();

    constructor(string memory baseUri) ERC1155(baseUri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function _setUriIfProvided(uint256 tokenId, string memory uri_) internal {
        if (bytes(uri_).length == 0) return;
        if (_uriSet[tokenId]) revert UriAlreadySet(tokenId);
        _setURI(tokenId, uri_);
        _uriSet[tokenId] = true;
    }

    /// @notice 단일 타입을 민트. uri_가 비어있지 않으면 해당 tokenId의 URI를 설정.
    function mintOrnament(address to, uint256 tokenId, uint256 amount, string memory uri_)
        external
        onlyRole(MINTER_ROLE)
    {
        _setUriIfProvided(tokenId, uri_);
        _mint(to, tokenId, amount, "");
    }

    /// @notice 여러 타입을 한 번에 민트. uris가 비어있지 않다면 ids와 길이가 같아야 함.
    function mintBatchOrnaments(address to, uint256[] memory ids, uint256[] memory amounts, string[] memory uris)
        external
        onlyRole(MINTER_ROLE)
    {
        if (ids.length != amounts.length) revert ArrayLengthMismatch();
        if (uris.length > 0) {
            if (uris.length != ids.length) revert ArrayLengthMismatch();
            // 단순 중복 체크(O(n^2)).
            for (uint256 i = 0; i < ids.length; i++) {
                for (uint256 j = i + 1; j < ids.length; j++) {
                    if (ids[i] == ids[j]) revert ArrayLengthMismatch();
                }
            }
            for (uint256 i = 0; i < ids.length; i++) {
                _setUriIfProvided(ids[i], uris[i]);
            }
        }
        _mintBatch(to, ids, amounts, "");
    }

    // ===== Overrides =====
    function uri(uint256 tokenId) public view override(ERC1155, ERC1155URIStorage) returns (string memory) {
        return super.uri(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }
}
