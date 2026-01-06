// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AAVEFlashloan} from "../src/AAVEFlashloan.sol";
import {UniswapFlashSwap} from "../src/UniswapFlashSwap.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract FlashloanTest is Test {
    AAVEFlashloan public aaveFlashloan;
    UniswapFlashSwap public uniswapFlashSwap;
    
    address public owner = address(1);
    address public user = address(2);
    
    function setUp() public {
        // Deploy AAVE Flashloan
        AAVEFlashloan impl = new AAVEFlashloan();
        bytes memory initData = abi.encodeWithSelector(
            AAVEFlashloan.initialize.selector,
            owner,
            address(0x123), // mock pool
            50, // 0.5% fee
            10 // 0.1% min profit
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        aaveFlashloan = AAVEFlashloan(address(proxy));
        
        // Deploy Uniswap Flash Swap
        UniswapFlashSwap uniswapImpl = new UniswapFlashSwap();
        bytes memory uniswapInitData = abi.encodeWithSelector(
            UniswapFlashSwap.initialize.selector,
            owner,
            50,
            10
        );
        ERC1967Proxy uniswapProxy = new ERC1967Proxy(address(uniswapImpl), uniswapInitData);
        uniswapFlashSwap = UniswapFlashSwap(address(uniswapProxy));
    }
    
    function testAAVEFlashloanInitialization() public view {
        assertEq(aaveFlashloan.owner(), owner);
        assertEq(aaveFlashloan.feeBps(), 50);
        assertEq(aaveFlashloan.minProfitBps(), 10);
    }
    
    function testUniswapFlashSwapInitialization() public view {
        assertEq(uniswapFlashSwap.owner(), owner);
        assertEq(uniswapFlashSwap.feeBps(), 50);
        assertEq(uniswapFlashSwap.minProfitBps(), 10);
    }
    
    function testSetFee() public {
        vm.prank(owner);
        aaveFlashloan.setFee(100);
        assertEq(aaveFlashloan.feeBps(), 100);
    }
    
    function testSetFeeRevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.setFee(100);
    }
    
    function testPause() public {
        vm.prank(owner);
        aaveFlashloan.pause();
        assertTrue(aaveFlashloan.paused());
    }
}

