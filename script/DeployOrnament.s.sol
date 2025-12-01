// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";

contract DeployOrnament is Script {
    function run() external returns (OrnamentNFT ornament) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address minter = vm.envOr("MINTER_ADDRESS", deployer);
        string memory baseUri = vm.envOr("ORNAMENT_BASE_URI", string(""));

        vm.startBroadcast(deployerKey);
        ornament = new OrnamentNFT(baseUri);
        if (minter != deployer) {
            ornament.grantRole(ornament.MINTER_ROLE(), minter);
        }
        vm.stopBroadcast();
    }
}
