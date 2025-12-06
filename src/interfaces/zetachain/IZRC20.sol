// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IZRC20
 * @notice Interface for ZRC20 tokens on ZetaChain
 * @dev ZRC20 tokens represent bridged assets from connected chains
 */
interface IZRC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    
    /**
     * @notice Withdraw ZRC20 back to the connected chain
     * @param to Recipient address on the connected chain
     * @param amount Amount to withdraw
     * @return success Whether the withdrawal was initiated
     */
    function withdraw(bytes memory to, uint256 amount) external returns (bool);
    
    /**
     * @notice Get the gas fee required for withdrawal
     * @return gasFee The gas fee in ZRC20 tokens
     */
    function withdrawGasFee() external view returns (address, uint256);
}




