// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title RevertContext
 * @notice Context information passed to onRevert when a cross-chain call fails
 */
struct RevertContext {
    address asset; // The asset involved (ZRC20 on ZetaChain)
    uint64 amount; // Amount that failed to transfer
    bytes revertMessage; // Identifier/reason for the revert
}

/**
 * @title Revertable
 * @notice Interface for handling cross-chain call failures
 * @dev Implement this to handle refund/rollback logic when outgoing calls fail
 */
interface Revertable {
    /**
     * @notice Called by ZetaChain Gateway when an outgoing cross-chain call fails
     * @param context Revert context containing failure details
     */
    function onRevert(RevertContext calldata context) external;
}


