// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ITreeNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function addOrnamentToTree(uint256 treeId, uint256 ornamentId, address caller) external;
}

contract OrnamentNFT is ERC1155, ERC1155Supply, ERC1155URIStorage, AccessControl, EIP712 {
    using SafeERC20 for IERC20;

    uint256 public constant CUSTOM_TOKEN_START = 1001;

    struct OrnamentMintPermit {
        address to;
        uint256 tokenId;
        uint256 treeId;
        uint256 deadline;
        uint256 nonce;
    }

    bytes32 private constant ORNAMENT_MINT_PERMIT_TYPEHASH = keccak256(
        "OrnamentMintPermit(address to,uint256 tokenId,uint256 treeId,uint256 deadline,uint256 nonce)"
    );

    address public signer;
    address public treeNFT;
    IERC20 public paymentToken;
    uint256 public mintFee;
    uint256 public nextCustomTokenId;

    mapping(address => uint256) public nonces;
    mapping(uint256 => bool) public ornamentRegistered;

    error InvalidSignature();
    error ExpiredDeadline();
    error InvalidNonce();
    error OrnamentNotRegistered();
    error OrnamentAlreadyRegistered();
    error InvalidTokenId();
    error NotTreeOwner();
    error PaymentTokenNotSet();
    error MintFeeNotSet();
    error ArrayLengthMismatch();

    event OrnamentMinted(uint256 indexed tokenId, address indexed to, uint256 indexed treeId);
    event CustomOrnamentMinted(uint256 indexed tokenId, address indexed to, uint256 indexed treeId, string uri);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event OrnamentRegistered(uint256 indexed tokenId, string uri);
    event OrnamentUriUpdated(uint256 indexed tokenId, string uri);
    event PaymentTokenUpdated(address indexed token);
    event MintFeeUpdated(uint256 fee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    constructor(
        address _signer,
        address _treeNFT,
        string memory baseUri
    ) ERC1155(baseUri) EIP712("ZetaOrnament", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        signer = _signer;
        treeNFT = _treeNFT;
        nextCustomTokenId = CUSTOM_TOKEN_START;
        emit SignerUpdated(address(0), _signer);
    }

    function mintWithSignature(OrnamentMintPermit calldata permit, bytes calldata signature) external {
        if (block.timestamp > permit.deadline) revert ExpiredDeadline();
        if (permit.nonce != nonces[permit.to]) revert InvalidNonce();
        if (!ornamentRegistered[permit.tokenId]) revert OrnamentNotRegistered();

        bytes32 structHash = keccak256(
            abi.encode(
                ORNAMENT_MINT_PERMIT_TYPEHASH,
                permit.to,
                permit.tokenId,
                permit.treeId,
                permit.deadline,
                permit.nonce
            )
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(hash, signature);

        if (recovered != signer) revert InvalidSignature();

        nonces[permit.to]++;
        _mint(permit.to, permit.tokenId, 1, "");

        // Add ornament to tree (permit.to is the tree owner)
        ITreeNFT(treeNFT).addOrnamentToTree(permit.treeId, permit.tokenId, permit.to);

        emit OrnamentMinted(permit.tokenId, permit.to, permit.treeId);
    }

    function mintCustomOrnament(uint256 treeId, string calldata ornamentUri) external {
        if (address(paymentToken) == address(0)) revert PaymentTokenNotSet();
        if (mintFee == 0) revert MintFeeNotSet();

        // Check tree ownership
        if (ITreeNFT(treeNFT).ownerOf(treeId) != msg.sender) revert NotTreeOwner();

        // Collect payment
        paymentToken.safeTransferFrom(msg.sender, address(this), mintFee);

        // Mint custom ornament
        uint256 tokenId = nextCustomTokenId++;
        _mint(msg.sender, tokenId, 1, "");
        _setURI(tokenId, ornamentUri);
        ornamentRegistered[tokenId] = true;

        // Add ornament to tree
        ITreeNFT(treeNFT).addOrnamentToTree(treeId, tokenId, msg.sender);

        emit CustomOrnamentMinted(tokenId, msg.sender, treeId, ornamentUri);
    }

    function setSigner(address _signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldSigner = signer;
        signer = _signer;
        emit SignerUpdated(oldSigner, _signer);
    }

    function setTreeNFT(address _treeNFT) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treeNFT = _treeNFT;
    }

    function registerOrnament(uint256 tokenId, string calldata ornamentUri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _registerOrnament(tokenId, ornamentUri);
    }

    function registerOrnaments(
        uint256[] calldata tokenIds,
        string[] calldata uris
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenIds.length != uris.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _registerOrnament(tokenIds[i], uris[i]);
        }
    }

    function _registerOrnament(uint256 tokenId, string calldata ornamentUri) internal {
        if (tokenId >= CUSTOM_TOKEN_START) revert InvalidTokenId();
        if (ornamentRegistered[tokenId]) revert OrnamentAlreadyRegistered();

        ornamentRegistered[tokenId] = true;
        if (bytes(ornamentUri).length > 0) {
            _setURI(tokenId, ornamentUri);
        }
        emit OrnamentRegistered(tokenId, ornamentUri);
    }

    function setOrnamentUri(uint256 tokenId, string calldata ornamentUri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!ornamentRegistered[tokenId]) revert OrnamentNotRegistered();
        _setURI(tokenId, ornamentUri);
        emit OrnamentUriUpdated(tokenId, ornamentUri);
    }

    function setPaymentToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        paymentToken = IERC20(token);
        emit PaymentTokenUpdated(token);
    }

    function setMintFee(uint256 fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintFee = fee;
        emit MintFeeUpdated(fee);
    }

    function withdrawFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = paymentToken.balanceOf(address(this));
        paymentToken.safeTransfer(to, balance);
        emit FeesWithdrawn(to, balance);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
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
