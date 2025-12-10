// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";

contract MintMockERC20 is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address tokenAddress = vm.envAddress("MOCK_ERC20_ADDRESS");
        
        // Get recipient address from environment variable or script argument
        address recipient = vm.envOr("RECIPIENT_ADDRESS", address(0));
        
        // If not set via env, try to read from script argument
        if (recipient == address(0)) {
            // Try to get from vm.addr() if private key is provided
            try vm.envUint("RECIPIENT_PRIVATE_KEY") returns (uint256 recipientKey) {
                recipient = vm.addr(recipientKey);
            } catch {
                // If no recipient specified, use deployer
                recipient = vm.addr(deployerKey);
            }
        }

        MockERC20 token = MockERC20(tokenAddress);

        console.log("Token address:", tokenAddress);
        console.log("Recipient address:", recipient);
        console.log("Recipient balance before:", token.balanceOf(recipient));

        vm.startBroadcast(deployerKey);

        // Mint to recipient (anyone can call mintTo, always mints 100 tokens)
        // USDC uses 6 decimals, so 100 tokens = 100 * 10^6
        token.mintTo(recipient);

        console.log("Recipient balance after:", token.balanceOf(recipient));
        console.log("Minted amount:", token.MINT_AMOUNT());

        vm.stopBroadcast();
    }
}

