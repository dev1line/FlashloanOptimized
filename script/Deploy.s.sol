// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AAVEFlashloan} from "../src/AAVEFlashloan.sol";
import {UniswapFlashSwap} from "../src/UniswapFlashSwap.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy AAVE Flashloan
        console.log("Deploying AAVE Flashloan...");
        AAVEFlashloan aaveImpl = new AAVEFlashloan();

        // Initialize data
        bytes memory initData = abi.encodeWithSelector(
            AAVEFlashloan.initialize.selector,
            deployer, // owner
            address(0), // pool - set actual AAVE pool address
            50, // feeBps (0.5%)
            10 // minProfitBps (0.1%)
        );

        ERC1967Proxy aaveProxy = new ERC1967Proxy(address(aaveImpl), initData);

        console.log("AAVE Flashloan deployed at:", address(aaveProxy));

        // Deploy Uniswap Flash Swap
        console.log("Deploying Uniswap Flash Swap...");
        UniswapFlashSwap uniswapImpl = new UniswapFlashSwap();

        bytes memory uniswapInitData = abi.encodeWithSelector(
            UniswapFlashSwap.initialize.selector,
            deployer, // owner
            50, // feeBps (0.5%)
            10 // minProfitBps (0.1%)
        );

        ERC1967Proxy uniswapProxy = new ERC1967Proxy(address(uniswapImpl), uniswapInitData);

        console.log("Uniswap Flash Swap deployed at:", address(uniswapProxy));

        vm.stopBroadcast();
    }
}
