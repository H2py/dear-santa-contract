// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UniversalContract, MessageContext} from "./interfaces/zetachain/UniversalContract.sol";
import {Revertable, RevertContext} from "./interfaces/zetachain/Revertable.sol";
import {IZRC20} from "./interfaces/zetachain/IZRC20.sol";
import {ITreeNFT} from "./interfaces/ITreeNFT.sol";
import {IOrnamentNFT} from "./interfaces/IOrnamentNFT.sol";

/**
 * @title UniversalApp
 * @notice Cross-chain relay contract for Dear Santa NFT system
 * @dev Receives calls from Base via ZetaChain Gateway and routes to TreeNFT/OrnamentNFT
 */
contract UniversalApp is 
    Initializable,
    UniversalContract,
    Revertable,
    AccessControlUpgradeable,
    UUPSUpgradeable 
{
    // ===== Action Types =====
    bytes1 public constant ACTION_MINT_TREE = 0x01;
    bytes1 public constant ACTION_MINT_ORNAMENT_FREE = 0x02;
    bytes1 public constant ACTION_MINT_ORNAMENT_CUSTOM = 0x03;
    bytes1 public constant ACTION_ADD_ORNAMENT = 0x04;

    // ===== State Variables =====
    address public treeNFT;
    address public ornamentNFT;
    address public feeReceiver;
    address public usdcZRC20;
    uint256 public customOrnamentPrice;

    // ===== Errors =====
    error InvalidAction();
    error InvalidPaymentToken();
    error InsufficientPayment();
    error InvalidAddress();
    error TransferFailed();

    // ===== Events =====
    event TreeMintedCrossChain(address indexed user, uint256 indexed treeId);
    event OrnamentMintedCrossChain(address indexed user, uint256 indexed ornamentId);
    event CustomOrnamentMintedCrossChain(address indexed user, uint256 amountPaid);
    event OrnamentAttachedCrossChain(address indexed user, uint256 indexed treeId, uint256 indexed ornamentId);
    event RevertHandled(address asset, uint64 amount, bytes message);
    event ConfigUpdated(string indexed configType, address indexed value);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _gateway) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        gateway = _gateway;
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ===== Callable Implementation =====

    /**
     * @notice Called by ZetaChain Gateway when a cross-chain call is received
     * @param context Message context containing sender info
     * @param zrc20 ZRC20 token address (zero for no-asset calls)
     * @param amount Amount of ZRC20 tokens received
     * @param message Encoded action and parameters
     */
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override onlyGateway {
        // Extract action type
        bytes1 action = bytes1(message[0]);

        if (action == ACTION_MINT_TREE) {
            _handleMintTree(message[1:]);
        } else if (action == ACTION_MINT_ORNAMENT_FREE) {
            _handleMintOrnamentFree(message[1:]);
        } else if (action == ACTION_MINT_ORNAMENT_CUSTOM) {
            _handleMintOrnamentCustom(context.senderEVM, zrc20, amount, message[1:]);
        } else if (action == ACTION_ADD_ORNAMENT) {
            _handleAddOrnament(message[1:]);
        } else {
            revert InvalidAction();
        }
    }

    /**
     * @notice Handle tree minting with signature
     * @param data Encoded (MintPermit, signature)
     */
    function _handleMintTree(bytes calldata data) internal {
        (
            ITreeNFT.MintPermit memory permit,
            bytes memory signature
        ) = abi.decode(data, (ITreeNFT.MintPermit, bytes));

        ITreeNFT(treeNFT).mintWithSignature(permit, signature);

        emit TreeMintedCrossChain(permit.to, permit.treeId);
    }

    /**
     * @notice Handle free ornament minting with signature
     * @param data Encoded (OrnamentMintPermit, signature)
     */
    function _handleMintOrnamentFree(bytes calldata data) internal {
        (
            IOrnamentNFT.OrnamentMintPermit memory permit,
            bytes memory signature
        ) = abi.decode(data, (IOrnamentNFT.OrnamentMintPermit, bytes));

        IOrnamentNFT(ornamentNFT).mintWithSignature(permit, signature);

        emit OrnamentMintedCrossChain(permit.to, permit.tokenId);
    }

    /**
     * @notice Handle paid custom ornament minting
     * @dev For depositAndCall, tokens are sent to this contract as ZRC20
     * @param user User address on source chain (for event purposes)
     * @param zrc20 ZRC20 token received from depositAndCall
     * @param amount Amount of ZRC20 tokens received
     * @param data Encoded (recipient, ornamentUri)
     */
    function _handleMintOrnamentCustom(
        address user,
        address zrc20,
        uint256 amount,
        bytes calldata data
    ) internal {
        // Validate payment token
        if (zrc20 != usdcZRC20) revert InvalidPaymentToken();
        if (amount < customOrnamentPrice) revert InsufficientPayment();

        // Decode parameters
        (address recipient, string memory ornamentUri) = abi.decode(data, (address, string));
        
        // Use user as recipient if not specified
        if (recipient == address(0)) {
            recipient = user;
        }

        // Approve OrnamentNFT to spend payment
        IZRC20(usdcZRC20).approve(ornamentNFT, customOrnamentPrice);

        // Mint custom ornament (OrnamentNFT will pull payment)
        IOrnamentNFT(ornamentNFT).mintCustomOrnamentFor(recipient, ornamentUri);

        // Forward remaining balance to feeReceiver (if any excess)
        uint256 remaining = amount - customOrnamentPrice;
        if (remaining > 0 && feeReceiver != address(0)) {
            bool success = IZRC20(usdcZRC20).transfer(feeReceiver, remaining);
            if (!success) revert TransferFailed();
        }

        emit CustomOrnamentMintedCrossChain(recipient, amount);
    }

    /**
     * @notice Handle ornament attachment to tree
     * @param data Encoded (user, treeId, ornamentId)
     */
    function _handleAddOrnament(bytes calldata data) internal {
        (address user, uint256 treeId, uint256 ornamentId) = abi.decode(data, (address, uint256, uint256));

        // Call TreeNFT.addOrnamentToTreeFor which burns the ornament on behalf of user
        ITreeNFT(treeNFT).addOrnamentToTreeFor(user, treeId, ornamentId);

        emit OrnamentAttachedCrossChain(user, treeId, ornamentId);
    }

    // ===== Revertable Implementation =====

    /**
     * @notice Handle failed cross-chain calls
     * @param context Revert context with failure details
     */
    function onRevert(RevertContext calldata context) external override onlyGateway {
        // Log the revert for debugging/indexing
        emit RevertHandled(context.asset, context.amount, context.revertMessage);
        
        // Note: The actual refund is handled by ZetaChain protocol
        // based on revertAddress specified in the original call
    }

    // ===== Admin Functions =====

    function setTreeNFT(address _treeNFT) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treeNFT == address(0)) revert InvalidAddress();
        treeNFT = _treeNFT;
        emit ConfigUpdated("treeNFT", _treeNFT);
    }

    function setOrnamentNFT(address _ornamentNFT) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_ornamentNFT == address(0)) revert InvalidAddress();
        ornamentNFT = _ornamentNFT;
        emit ConfigUpdated("ornamentNFT", _ornamentNFT);
    }

    function setFeeReceiver(address _feeReceiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeReceiver == address(0)) revert InvalidAddress();
        feeReceiver = _feeReceiver;
        emit ConfigUpdated("feeReceiver", _feeReceiver);
    }

    function setUsdcZRC20(address _usdcZRC20) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_usdcZRC20 == address(0)) revert InvalidAddress();
        usdcZRC20 = _usdcZRC20;
        emit ConfigUpdated("usdcZRC20", _usdcZRC20);
    }

    function setCustomOrnamentPrice(uint256 _price) external onlyRole(DEFAULT_ADMIN_ROLE) {
        customOrnamentPrice = _price;
    }

    function setGateway(address _gateway) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_gateway == address(0)) revert InvalidAddress();
        gateway = _gateway;
        emit ConfigUpdated("gateway", _gateway);
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @param token Token address to withdraw
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert InvalidAddress();
        bool success = IZRC20(token).transfer(to, amount);
        if (!success) revert TransferFailed();
    }

    /// @notice Receive ETH (for payable onCall)
    receive() external payable {}
}
