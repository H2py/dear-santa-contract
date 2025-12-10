// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UniversalContract, MessageContext} from "./interfaces/zetachain/UniversalContract.sol";
import {Revertable, RevertContext} from "./interfaces/zetachain/Revertable.sol";
import {ITreeNFT} from "./interfaces/ITreeNFT.sol";
import {IOrnamentNFT} from "./interfaces/IOrnamentNFT.sol";

/**
 * @title UniversalApp
 * @notice Cross-chain relay contract for Dear Santa NFT system
 * @dev Receives calls from Base via ZetaChain Gateway and routes to TreeNFT/OrnamentNFT
 */
contract UniversalApp is Initializable, UniversalContract, Revertable, AccessControlUpgradeable, UUPSUpgradeable {
    // ===== Action Types =====
    bytes1 public constant ACTION_MINT_TREE = 0x01;
    bytes1 public constant ACTION_MINT_ORNAMENT_FREE = 0x02;
    bytes1 public constant ACTION_ADD_ORNAMENT = 0x04;

    // ===== State Variables =====
    address public treeNFT;
    address public ornamentNFT;

    // ===== Errors =====
    error InvalidAction();
    error InvalidAddress();

    // ===== Events =====
    event TreeMintedCrossChain(address indexed user, uint256 indexed treeId);
    event OrnamentMintedCrossChain(address indexed user, uint256 indexed ornamentId);
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
     * @param message Encoded action and parameters
     */
    function onCall(MessageContext calldata, address, uint256, bytes calldata message)
        external
        override
        onlyGateway
    {
        // Extract action type
        bytes1 action = bytes1(message[0]);

        if (action == ACTION_MINT_TREE) {
            _handleMintTree(message[1:]);
        } else if (action == ACTION_MINT_ORNAMENT_FREE) {
            _handleMintOrnamentFree(message[1:]);
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
        (ITreeNFT.MintPermit memory permit, bytes memory signature) = abi.decode(data, (ITreeNFT.MintPermit, bytes));

        ITreeNFT(treeNFT).mintWithSignature(permit, signature);

        emit TreeMintedCrossChain(permit.to, permit.treeId);
    }

    /**
     * @notice Handle free ornament minting with signature
     * @param data Encoded (OrnamentMintPermit, signature)
     */
    function _handleMintOrnamentFree(bytes calldata data) internal {
        (IOrnamentNFT.OrnamentMintPermit memory permit, bytes memory signature) =
            abi.decode(data, (IOrnamentNFT.OrnamentMintPermit, bytes));

        IOrnamentNFT(ornamentNFT).mintWithSignature(permit, signature);

        emit OrnamentMintedCrossChain(permit.to, permit.tokenId);
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

    function setGateway(address _gateway) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_gateway == address(0)) revert InvalidAddress();
        gateway = _gateway;
        emit ConfigUpdated("gateway", _gateway);
    }
}
