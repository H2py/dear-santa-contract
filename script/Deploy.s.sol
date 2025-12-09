// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TreeNFT} from "../src/TreeNFT.sol";
import {OrnamentNFT} from "../src/OrnamentNFT.sol";
import {UniversalApp} from "../src/UniversalApp.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external returns (TreeNFT tree, OrnamentNFT ornament, UniversalApp universalApp) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address signer = vm.envOr("SIGNER_ADDRESS", deployer);
        address gateway = vm.envOr("GATEWAY_ADDRESS", deployer);

        vm.startBroadcast(deployerKey);

        // Deploy TreeNFT
        tree = _deployTree(signer);

        // Deploy OrnamentNFT
        ornament = _deployOrnament(signer);

        // Deploy UniversalApp
        universalApp = _deployUniversalApp(gateway);

        // Link contracts
        tree.setOrnamentNFT(address(ornament));
        tree.setUniversalApp(address(universalApp));
        ornament.setTreeNFT(address(tree));
        universalApp.setTreeNFT(address(tree));
        universalApp.setOrnamentNFT(address(ornament));

        vm.stopBroadcast();

        _logResults(tree, ornament, universalApp);
    }

    function _deployTree(address signer) internal returns (TreeNFT) {
        TreeNFT impl = new TreeNFT();
        bytes memory initData = abi.encodeCall(TreeNFT.initialize, (signer));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console.log("TreeNFT deployed at:", address(proxy));
        return TreeNFT(address(proxy));
    }

    function _deployOrnament(address signer) internal returns (OrnamentNFT) {
        OrnamentNFT impl = new OrnamentNFT();
        bytes memory initData = abi.encodeCall(OrnamentNFT.initialize, (signer, ""));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console.log("OrnamentNFT deployed at:", address(proxy));
        return OrnamentNFT(address(proxy));
    }

    function _deployUniversalApp(address gateway) internal returns (UniversalApp) {
        UniversalApp impl = new UniversalApp();
        bytes memory initData = abi.encodeCall(UniversalApp.initialize, (gateway));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console.log("UniversalApp deployed at:", address(proxy));
        return UniversalApp(payable(address(proxy)));
    }

    function _logResults(TreeNFT tree, OrnamentNFT ornament, UniversalApp universalApp) internal pure {
        console.log("");
        console.log("==========================================");
        console.log("Deployment Complete!");
        console.log("==========================================");
        console.log("TreeNFT:      ", address(tree));
        console.log("OrnamentNFT:  ", address(ornament));
        console.log("UniversalApp: ", address(universalApp));
        console.log("==========================================");
    }
}
