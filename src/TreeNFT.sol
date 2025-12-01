// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TreeNFT is ERC721Enumerable, ERC721URIStorage, AccessControl, EIP712 {
    uint256 public constant MAX_DISPLAY = 10;

    struct MintPermit {
        address to;
        uint256 treeId;
        uint256 backgroundId;
        string uri;
        uint256 deadline;
        uint256 nonce;
    }

    bytes32 private constant MINT_PERMIT_TYPEHASH = keccak256(
        "MintPermit(address to,uint256 treeId,uint256 backgroundId,string uri,uint256 deadline,uint256 nonce)"
    );

    address public signer;
    address public ornamentNFT;
    mapping(address => uint256) public nonces;
    mapping(uint256 => uint256) public treeBackground; // treeId => backgroundId
    mapping(uint256 => string) public backgroundUri; // backgroundId => URI
    mapping(uint256 => bool) public backgroundRegistered;
    mapping(uint256 => uint256[]) private _treeOrnaments; // treeId => ornamentIds

    error InvalidSignature();
    error ExpiredDeadline();
    error InvalidNonce();
    error BackgroundNotRegistered();
    error BackgroundAlreadyRegistered();
    error NotTreeOwner();
    error NotAuthorized();
    error InvalidDisplayLength();
    error InvalidOrnamentIndex();
    error ArrayLengthMismatch();

    event TreeMinted(uint256 indexed treeId, address indexed to, uint256 backgroundId);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event OrnamentNFTUpdated(address indexed ornamentNFT);
    event BackgroundRegistered(uint256 indexed backgroundId, string uri);
    event BackgroundUriUpdated(uint256 indexed backgroundId, string uri);
    event OrnamentAdded(uint256 indexed treeId, uint256 indexed ornamentId);
    event DisplayOrderUpdated(uint256 indexed treeId);
    event OrnamentsPromoted(uint256 indexed treeId);

    constructor(address _signer) ERC721("Zeta Tree", "TREE") EIP712("ZetaTree", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        signer = _signer;
        emit SignerUpdated(address(0), _signer);
    }

    function mintWithSignature(MintPermit calldata permit, bytes calldata signature) external {
        if (block.timestamp > permit.deadline) revert ExpiredDeadline();
        if (permit.nonce != nonces[permit.to]) revert InvalidNonce();
        if (!backgroundRegistered[permit.backgroundId]) revert BackgroundNotRegistered();

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
        bytes32 hash = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(hash, signature);

        if (recovered != signer) revert InvalidSignature();

        nonces[permit.to]++;
        _safeMint(permit.to, permit.treeId);
        _setTokenURI(permit.treeId, permit.uri);
        treeBackground[permit.treeId] = permit.backgroundId;

        emit TreeMinted(permit.treeId, permit.to, permit.backgroundId);
    }

    function setSigner(address _signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldSigner = signer;
        signer = _signer;
        emit SignerUpdated(oldSigner, _signer);
    }

    function registerBackground(uint256 backgroundId, string calldata uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (backgroundRegistered[backgroundId]) revert BackgroundAlreadyRegistered();
        backgroundRegistered[backgroundId] = true;
        backgroundUri[backgroundId] = uri;
        emit BackgroundRegistered(backgroundId, uri);
    }

    function updateBackgroundUri(uint256 backgroundId, string calldata uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!backgroundRegistered[backgroundId]) revert BackgroundNotRegistered();
        backgroundUri[backgroundId] = uri;
        emit BackgroundUriUpdated(backgroundId, uri);
    }

    function setOrnamentNFT(address _ornamentNFT) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ornamentNFT = _ornamentNFT;
        emit OrnamentNFTUpdated(_ornamentNFT);
    }

    /// @notice Add ornament to tree. Can be called by tree owner or OrnamentNFT contract
    /// @param treeId The tree to add ornament to
    /// @param ornamentId The ornament token ID
    /// @param caller The actual user (used when called from OrnamentNFT)
    function addOrnamentToTree(uint256 treeId, uint256 ornamentId, address caller) external {
        if (msg.sender == ornamentNFT) {
            if (ownerOf(treeId) != caller) revert NotTreeOwner();
        } else {
            if (ownerOf(treeId) != msg.sender) revert NotTreeOwner();
        }
        _treeOrnaments[treeId].push(ornamentId);
        emit OrnamentAdded(treeId, ornamentId);
    }

    /// @notice Add ornament to tree (convenience function for direct calls)
    function addOrnamentToTree(uint256 treeId, uint256 ornamentId) external {
        if (ownerOf(treeId) != msg.sender) revert NotTreeOwner();
        _treeOrnaments[treeId].push(ornamentId);
        emit OrnamentAdded(treeId, ornamentId);
    }

    function setDisplayOrder(uint256 treeId, uint256[] calldata newOrder) external {
        if (ownerOf(treeId) != msg.sender) revert NotTreeOwner();
        if (newOrder.length != MAX_DISPLAY) revert InvalidDisplayLength();

        uint256[] storage ornaments = _treeOrnaments[treeId];
        uint256 len = ornaments.length;
        if (len < MAX_DISPLAY) revert InvalidDisplayLength();

        // Copy original values to avoid overwrite issues
        uint256[] memory original = new uint256[](MAX_DISPLAY);
        for (uint256 i = 0; i < MAX_DISPLAY; i++) {
            original[i] = ornaments[i];
        }

        // Apply new order using original values
        for (uint256 i = 0; i < MAX_DISPLAY; i++) {
            if (newOrder[i] >= MAX_DISPLAY) revert InvalidOrnamentIndex();
            ornaments[i] = original[newOrder[i]];
        }

        emit DisplayOrderUpdated(treeId);
    }

    function promoteOrnaments(
        uint256 treeId,
        uint256[] calldata displayIdxs,
        uint256[] calldata reserveIdxs
    ) external {
        if (ownerOf(treeId) != msg.sender) revert NotTreeOwner();
        if (displayIdxs.length != reserveIdxs.length) revert ArrayLengthMismatch();

        uint256[] storage ornaments = _treeOrnaments[treeId];
        uint256 len = ornaments.length;

        for (uint256 i = 0; i < displayIdxs.length; i++) {
            uint256 dIdx = displayIdxs[i];
            uint256 rIdx = reserveIdxs[i];

            if (dIdx >= MAX_DISPLAY) revert InvalidOrnamentIndex();
            if (rIdx < MAX_DISPLAY || rIdx >= len) revert InvalidOrnamentIndex();

            (ornaments[dIdx], ornaments[rIdx]) = (ornaments[rIdx], ornaments[dIdx]);
        }

        emit OrnamentsPromoted(treeId);
    }

    function getTreeOrnaments(uint256 treeId) external view returns (uint256[] memory) {
        return _treeOrnaments[treeId];
    }

    function getDisplayOrnaments(uint256 treeId) external view returns (uint256[] memory) {
        uint256[] storage ornaments = _treeOrnaments[treeId];
        uint256 len = ornaments.length;
        uint256 displayLen = len < MAX_DISPLAY ? len : MAX_DISPLAY;

        uint256[] memory display = new uint256[](displayLen);
        for (uint256 i = 0; i < displayLen; i++) {
            display[i] = ornaments[i];
        }
        return display;
    }

    function getBackground(uint256 treeId) external view returns (uint256) {
        return treeBackground[treeId];
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ===== Overrides =====
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}
