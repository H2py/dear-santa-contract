// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Provides contextual information when executing a cross-chain call on ZetaChain.
/// @dev This struct helps identify the sender of the message across different blockchain environments.
struct MessageContext {
    /// @notice The address of the sender on the connected chain.
    /// @dev This field uses `bytes` to remain chain-agnostic, allowing support for both EVM and non-EVM chains.
    /// If the connected chain is an EVM chain, `senderEVM` will also be populated with the same value.
    bytes sender;
    /// @notice The sender's address in `address` type if the connected chain is an EVM-compatible chain.
    address senderEVM;
    /// @notice The chain ID of the connected chain.
    /// @dev This identifies the origin chain of the message, allowing contract logic to differentiate between sources.
    uint256 chainID;
}

/// @title UniversalContract
/// @notice Abstract contract for ZetaChain Universal Apps
/// @dev Contracts extending this abstract contract can handle incoming cross-chain messages
abstract contract UniversalContract {
    /// @notice The ZetaChain Gateway address
    address public gateway;

    error OnlyGateway();

    modifier onlyGateway() {
        if (msg.sender != gateway) revert OnlyGateway();
        _;
    }

    /// @notice Function to handle cross-chain calls with ZRC20 token transfers
    function onCall(MessageContext calldata context, address zrc20, uint256 amount, bytes calldata message)
        external
        virtual;
}
