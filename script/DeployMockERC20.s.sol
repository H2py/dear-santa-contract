// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";

contract DeployMockERC20 is Script {
    function run() external returns (MockERC20 token) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // Deploy MockERC20
        string memory name = vm.envOr("MOCK_TOKEN_NAME", string("Mock USDC"));
        string memory symbol = vm.envOr("MOCK_TOKEN_SYMBOL", string("USDC"));
        
        token = new MockERC20(name, symbol);

        console.log("MockERC20 deployed at:", address(token));
        console.log("Token name:", name);
        console.log("Token symbol:", symbol);
        console.log("Deployer balance:", token.balanceOf(deployer));

        vm.stopBroadcast();
    }
}

