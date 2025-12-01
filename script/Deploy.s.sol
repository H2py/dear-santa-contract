// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TreeNFT} from "../src/TreeNFT.sol";

contract Deploy is Script {
    function run() external returns (TreeNFT tree) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address minter = vm.envOr("MINTER_ADDRESS", deployer);

        vm.startBroadcast(deployerKey);
        tree = new TreeNFT();

        if (minter != deployer) {
            tree.grantRole(tree.MINTER_ROLE(), minter);
        }

        vm.stopBroadcast();
    }
}
