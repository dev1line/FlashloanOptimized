// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AAVEFlashloan} from "../src/AAVEFlashloan.sol";
import {UniswapFlashSwap} from "../src/UniswapFlashSwap.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAAVEPool} from "./mocks/MockAAVEPool.sol";
import {MockUniswapPool} from "./mocks/MockUniswapPool.sol";
import {MockWorkflow} from "./mocks/MockWorkflow.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/**
 * @title IntegrationTest
 * @notice Integration tests for both AAVE and Uniswap flashloan contracts
 */
contract IntegrationTest is Test {
    AAVEFlashloan public aaveFlashloan;
    UniswapFlashSwap public uniswapFlashSwap;
    
    MockAAVEPool public aavePool;
    MockUniswapPool public uniswapPool;
    
    MockERC20 public token;
    MockERC20 public token0;
    MockERC20 public token1;
    
    MockWorkflow public workflow;
    
    address public owner = address(0x1);
    address public user = address(0x2);
    
    uint256 public constant AMOUNT = 1000e18;
    uint256 public constant FEE_BPS = 50;
    uint256 public constant MIN_PROFIT_BPS = 10;
    
    function setUp() public {
        // Setup tokens
        token = new MockERC20("Token", "TKN", 18);
        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);
        
        // Setup AAVE pool
        aavePool = new MockAAVEPool();
        token.mint(address(aavePool), 1000000e18);
        
        // Setup Uniswap pool
        uniswapPool = new MockUniswapPool(address(token0), address(token1), 3000);
        token0.mint(address(uniswapPool), 1000000e18);
        token1.mint(address(uniswapPool), 1000000e18);
        
        // Deploy AAVE Flashloan
        AAVEFlashloan aaveImpl = new AAVEFlashloan();
        bytes memory aaveInitData = abi.encodeWithSelector(
            AAVEFlashloan.initialize.selector,
            owner,
            address(aavePool),
            FEE_BPS,
            MIN_PROFIT_BPS
        );
        ERC1967Proxy aaveProxy = new ERC1967Proxy(address(aaveImpl), aaveInitData);
        aaveFlashloan = AAVEFlashloan(address(aaveProxy));
        
        // Deploy Uniswap Flash Swap
        UniswapFlashSwap uniswapImpl = new UniswapFlashSwap();
        bytes memory uniswapInitData = abi.encodeWithSelector(
            UniswapFlashSwap.initialize.selector,
            owner,
            FEE_BPS,
            MIN_PROFIT_BPS
        );
        ERC1967Proxy uniswapProxy = new ERC1967Proxy(address(uniswapImpl), uniswapInitData);
        uniswapFlashSwap = UniswapFlashSwap(address(uniswapProxy));
        
        // Deploy workflow
        workflow = new MockWorkflow(address(token), 10150); // 1.5% profit
        
        // Fund workflows with tokens for output (simulating DEX)
        token.mint(address(workflow), 1000000e18);
        token0.mint(address(workflow), 1000000e18);
        token1.mint(address(workflow), 1000000e18);
    }
    
    function test_AAVE_Flashloan_Integration() public {
        uint256 userBalanceBefore = token.balanceOf(user);
        
        vm.prank(user);
        bytes memory workflowData = abi.encode(address(token));
        aaveFlashloan.executeFlashloan(
            address(token),
            AMOUNT,
            address(workflow),
            workflowData
        );
        
        uint256 userBalanceAfter = token.balanceOf(user);
        assertGt(userBalanceAfter, userBalanceBefore, "User should profit");
        
        // Verify fees collected
        uint256 fees = token.balanceOf(address(aaveFlashloan));
        assertGt(fees, 0, "Fees should be collected");
    }
    
    function test_Uniswap_FlashSwap_Integration() public {
        // Create workflow that returns token1 (needed to pay back)
        MockWorkflow workflowToken1 = new MockWorkflow(address(token1), 10150);
        token1.mint(address(workflowToken1), 1000000e18);
        
        uint256 userBalanceBefore = token0.balanceOf(user);
        
        vm.prank(user);
        bytes memory workflowData = abi.encode(address(token1));
        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool),
            address(token0),
            address(token1),
            AMOUNT,
            address(workflowToken1),
            workflowData
        );
        
        uint256 userBalanceAfter = token0.balanceOf(user);
        assertGt(userBalanceAfter, userBalanceBefore, "User should profit");
    }
    
    function test_Multiple_Flashloans_Sequential() public {
        // Create workflow for Uniswap that returns token1
        MockWorkflow workflowToken1 = new MockWorkflow(address(token1), 10150);
        token1.mint(address(workflowToken1), 1000000e18);
        
        // Execute AAVE flashloan
        vm.startPrank(user);
        bytes memory workflowData = abi.encode(address(token));
        
        aaveFlashloan.executeFlashloan(
            address(token),
            AMOUNT,
            address(workflow),
            workflowData
        );
        
        // Execute Uniswap flash swap
        bytes memory uniswapWorkflowData = abi.encode(address(token1));
        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool),
            address(token0),
            address(token1),
            AMOUNT,
            address(workflowToken1),
            uniswapWorkflowData
        );
        
        vm.stopPrank();
        
        // Both should succeed
        assertGt(token.balanceOf(user), 0);
        assertGt(token0.balanceOf(user), 0);
    }
    
    function test_Fee_Collection_And_Withdrawal() public {
        address feeRecipient = address(0x3);
        
        // Execute flashloan to generate fees
        vm.prank(user);
        bytes memory workflowData = abi.encode(address(token));
        aaveFlashloan.executeFlashloan(
            address(token),
            AMOUNT,
            address(workflow),
            workflowData
        );
        
        uint256 feesBefore = token.balanceOf(address(aaveFlashloan));
        assertGt(feesBefore, 0, "Fees should be collected");
        
        // Withdraw fees
        vm.prank(owner);
        aaveFlashloan.withdrawFees(address(token), feeRecipient);
        
        uint256 feesAfter = token.balanceOf(address(aaveFlashloan));
        assertEq(feesAfter, 0, "Fees should be withdrawn");
        assertEq(token.balanceOf(feeRecipient), feesBefore, "Fee recipient should receive all fees");
    }
    
    function test_Upgrade_Contract() public {
        // Deploy new implementation
        AAVEFlashloan newImpl = new AAVEFlashloan();
        
        // Upgrade
        vm.prank(owner);
        aaveFlashloan.upgradeToAndCall(address(newImpl), "");
        
        // Verify still works
        assertEq(aaveFlashloan.owner(), owner);
        assertEq(aaveFlashloan.feeBps(), FEE_BPS);
    }
    
    function test_Pause_And_Resume() public {
        // Pause
        vm.prank(owner);
        aaveFlashloan.pause();
        assertTrue(aaveFlashloan.paused());
        
        // Try to execute (should fail)
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.executeFlashloan(
            address(token),
            AMOUNT,
            address(workflow),
            ""
        );
        
        // Unpause
        vm.prank(owner);
        aaveFlashloan.unpause();
        assertFalse(aaveFlashloan.paused());
        
        // Now should work
        vm.prank(user);
        bytes memory workflowData = abi.encode(address(token));
        aaveFlashloan.executeFlashloan(
            address(token),
            AMOUNT,
            address(workflow),
            workflowData
        );
    }
    
    function test_Fee_Configuration() public {
        // Change fee
        vm.prank(owner);
        aaveFlashloan.setFee(100); // 1%
        assertEq(aaveFlashloan.feeBps(), 100);
        
        // Change min profit
        vm.prank(owner);
        aaveFlashloan.setMinProfit(20); // 0.2%
        assertEq(aaveFlashloan.minProfitBps(), 20);
    }
}

