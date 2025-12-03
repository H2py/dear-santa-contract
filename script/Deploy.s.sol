// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TreeNFT} from "../src/TreeNFT.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external returns (TreeNFT tree, OrnamentNFT ornament) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address signer = vm.envOr("SIGNER_ADDRESS", deployer);

        vm.startBroadcast(deployerKey);

        // Deploy TreeNFT Implementation
        TreeNFT treeImpl = new TreeNFT();
        console.log("TreeNFT Implementation deployed at:", address(treeImpl));

        // Deploy TreeNFT Proxy
        bytes memory treeInitData = abi.encodeCall(TreeNFT.initialize, (signer));
        ERC1967Proxy treeProxy = new ERC1967Proxy(address(treeImpl), treeInitData);
        tree = TreeNFT(address(treeProxy));
        console.log("TreeNFT Proxy deployed at:", address(tree));

        // Deploy OrnamentNFT Implementation
        OrnamentNFT ornamentImpl = new OrnamentNFT();
        console.log("OrnamentNFT Implementation deployed at:", address(ornamentImpl));

        // Deploy OrnamentNFT Proxy
        bytes memory ornamentInitData = abi.encodeCall(OrnamentNFT.initialize, (signer, ""));
        ERC1967Proxy ornamentProxy = new ERC1967Proxy(address(ornamentImpl), ornamentInitData);
        ornament = OrnamentNFT(address(ornamentProxy));
        console.log("OrnamentNFT Proxy deployed at:", address(ornament));

        vm.stopBroadcast();
    }
}
