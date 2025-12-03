// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract TreeNFT is 
    Initializable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable,
    IERC1155Receiver 
{
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
    uint256 public registeredBackgroundCount;

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
    event OrnamentAdded(uint256 indexed treeId, uint256 indexed ornamentId, address indexed sender, uint256 index);
    event DisplayOrderUpdated(uint256 indexed treeId);
    event OrnamentsPromoted(uint256 indexed treeId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _signer) public initializer {
        __ERC721_init("Zeta Tree", "TREE");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __AccessControl_init();
        __EIP712_init("ZetaTree", "1");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        signer = _signer;
        emit SignerUpdated(address(0), _signer);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

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

    function registerBackgrounds(
        uint256[] calldata backgroundIds,
        string[] calldata uris
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (backgroundIds.length != uris.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < backgroundIds.length; i++) {
            _registerBackground(backgroundIds[i], uris[i]);
        }
    }

    function _registerBackground(uint256 backgroundId, string calldata uri) internal {
        if (backgroundRegistered[backgroundId]) revert BackgroundAlreadyRegistered();
        backgroundRegistered[backgroundId] = true;
        backgroundUri[backgroundId] = uri;
        registeredBackgroundCount++;
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

    /// @notice Add ornament to tree. Transfers ornament NFT to this contract.
    /// @param treeId The tree to add ornament to
    /// @param ornamentId The ornament token ID
    function addOrnamentToTree(uint256 treeId, uint256 ornamentId) external {
        if (ownerOf(treeId) != msg.sender) revert NotTreeOwner();
        
        // Transfer ornament from user to this contract
        IERC1155(ornamentNFT).safeTransferFrom(msg.sender, address(this), ornamentId, 1, "");
        
        _treeOrnaments[treeId].push(ornamentId);
        uint256 index = _treeOrnaments[treeId].length - 1;
        emit OrnamentAdded(treeId, ornamentId, msg.sender, index);
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

    // ===== ERC1155Receiver =====
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    // ===== Overrides =====
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}
