// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Deploy OrnamentNFT separately (with UUPS proxy)
contract DeployOrnament is Script {
    function run() external returns (OrnamentNFT ornament) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address signer = vm.envOr("SIGNER_ADDRESS", deployer);
        string memory baseUri = vm.envOr("ORNAMENT_BASE_URI", string(""));

        vm.startBroadcast(deployerKey);

        // Deploy Implementation
        OrnamentNFT ornamentImpl = new OrnamentNFT();
        console.log("OrnamentNFT Implementation deployed at:", address(ornamentImpl));

        // Deploy Proxy
        bytes memory initData = abi.encodeCall(OrnamentNFT.initialize, (signer, baseUri));
        ERC1967Proxy proxy = new ERC1967Proxy(address(ornamentImpl), initData);
        ornament = OrnamentNFT(address(proxy));
        console.log("OrnamentNFT Proxy deployed at:", address(ornament));

        vm.stopBroadcast();
    }
}
