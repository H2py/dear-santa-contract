// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TreeNFT} from "../src/TreeNFT.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";

contract Deploy is Script {
    function run() external returns (TreeNFT tree, OrnamentNFT ornament) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address signer = vm.envOr("SIGNER_ADDRESS", deployer);

        vm.startBroadcast(deployerKey);

        // Deploy TreeNFT
        tree = new TreeNFT(signer);
        console.log("TreeNFT deployed at:", address(tree));

        // Deploy OrnamentNFT
        ornament = new OrnamentNFT(signer, address(tree), "");
        console.log("OrnamentNFT deployed at:", address(ornament));

        // Set OrnamentNFT address in TreeNFT
        tree.setOrnamentNFT(address(ornament));
        console.log("OrnamentNFT set in TreeNFT");

        vm.stopBroadcast();
    }
}
