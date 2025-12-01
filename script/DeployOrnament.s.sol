// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";

/// @notice Deploy OrnamentNFT separately (requires existing TreeNFT address)
contract DeployOrnament is Script {
    function run() external returns (OrnamentNFT ornament) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address signer = vm.envOr("SIGNER_ADDRESS", deployer);
        address treeNFT = vm.envAddress("TREE_NFT_ADDRESS");
        string memory baseUri = vm.envOr("ORNAMENT_BASE_URI", string(""));

        vm.startBroadcast(deployerKey);
        ornament = new OrnamentNFT(signer, treeNFT, baseUri);
        console.log("OrnamentNFT deployed at:", address(ornament));
        vm.stopBroadcast();
    }
}
