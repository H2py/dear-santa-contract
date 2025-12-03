// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {ERC1155URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155URIStorageUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OrnamentNFT is 
    Initializable,
    ERC1155Upgradeable,
    ERC1155SupplyUpgradeable,
    ERC1155URIStorageUpgradeable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable 
{
    using SafeERC20 for IERC20;

    uint256 public constant CUSTOM_TOKEN_START = 1001;

    struct OrnamentMintPermit {
        address to;
        uint256 tokenId;
        uint256 deadline;
        uint256 nonce;
    }

    bytes32 private constant ORNAMENT_MINT_PERMIT_TYPEHASH = keccak256(
        "OrnamentMintPermit(address to,uint256 tokenId,uint256 deadline,uint256 nonce)"
    );

    address public signer;
    IERC20 public paymentToken;
    uint256 public mintFee;
    uint256 public nextCustomTokenId;

    mapping(address => uint256) public nonces;
    mapping(uint256 => bool) public ornamentRegistered;
    uint256 public registeredOrnamentCount;

    error InvalidSignature();
    error ExpiredDeadline();
    error InvalidNonce();
    error OrnamentNotRegistered();
    error OrnamentAlreadyRegistered();
    error InvalidTokenId();
    error PaymentTokenNotSet();
    error MintFeeNotSet();
    error ArrayLengthMismatch();

    event OrnamentMinted(uint256 indexed tokenId, address indexed to);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event OrnamentRegistered(uint256 indexed tokenId, string uri);
    event OrnamentUriUpdated(uint256 indexed tokenId, string uri);
    event PaymentTokenUpdated(address indexed token);
    event MintFeeUpdated(uint256 fee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _signer, string memory baseUri) public initializer {
        __ERC1155_init(baseUri);
        __ERC1155Supply_init();
        __ERC1155URIStorage_init();
        __AccessControl_init();
        __EIP712_init("ZetaOrnament", "1");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        signer = _signer;
        nextCustomTokenId = CUSTOM_TOKEN_START;
        emit SignerUpdated(address(0), _signer);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function mintWithSignature(OrnamentMintPermit calldata permit, bytes calldata signature) external {
        if (block.timestamp > permit.deadline) revert ExpiredDeadline();
        if (permit.nonce != nonces[permit.to]) revert InvalidNonce();
        if (!ornamentRegistered[permit.tokenId]) revert OrnamentNotRegistered();

        bytes32 structHash = keccak256(
            abi.encode(
                ORNAMENT_MINT_PERMIT_TYPEHASH,
                permit.to,
                permit.tokenId,
                permit.deadline,
                permit.nonce
            )
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(hash, signature);

        if (recovered != signer) revert InvalidSignature();

        nonces[permit.to]++;
        _mint(permit.to, permit.tokenId, 1, "");

        emit OrnamentMinted(permit.tokenId, permit.to);
    }

    function mintCustomOrnament(string calldata ornamentUri) external {
        if (address(paymentToken) == address(0)) revert PaymentTokenNotSet();
        if (mintFee == 0) revert MintFeeNotSet();

        // Collect payment
        paymentToken.safeTransferFrom(msg.sender, address(this), mintFee);

        // Mint custom ornament
        uint256 tokenId = nextCustomTokenId++;
        _mint(msg.sender, tokenId, 1, "");
        _setURI(tokenId, ornamentUri);
        ornamentRegistered[tokenId] = true;

        emit OrnamentMinted(tokenId, msg.sender);
    }

    function setSigner(address _signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldSigner = signer;
        signer = _signer;
        emit SignerUpdated(oldSigner, _signer);
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
        registeredOrnamentCount++;
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
    function uri(uint256 tokenId) public view override(ERC1155Upgradeable, ERC1155URIStorageUpgradeable) returns (string memory) {
        return super.uri(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlUpgradeable, ERC1155Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._update(from, to, ids, values);
    }
}
