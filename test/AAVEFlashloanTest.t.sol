// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AAVEFlashloan} from "../src/AAVEFlashloan.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAAVEPool} from "./mocks/MockAAVEPool.sol";
import {MockWorkflow, FailingWorkflow} from "./mocks/MockWorkflow.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract AAVEFlashloanTest is Test {
    AAVEFlashloan public flashloan;
    MockAAVEPool public pool;
    MockERC20 public token;
    MockWorkflow public workflow;
    FailingWorkflow public failingWorkflow;
    
    address public owner = address(0x1);
    address public user = address(0x2);
    address public feeRecipient = address(0x3);
    
    uint256 public constant FLASHLOAN_AMOUNT = 1000e18;
    uint256 public constant FEE_BPS = 50; // 0.5%
    uint256 public constant MIN_PROFIT_BPS = 10; // 0.1%
    
    event FlashloanExecuted(
        address indexed user,
        address indexed token,
        uint256 amount,
        bool success,
        uint256 profit,
        uint256 fee
    );
    
    function setUp() public {
        // Deploy mock token
        token = new MockERC20("Test Token", "TEST", 18);
        token.mint(address(this), 1000000e18);
        
        // Deploy mock AAVE pool
        pool = new MockAAVEPool();
        token.mint(address(pool), 1000000e18);
        token.approve(address(pool), type(uint256).max);
        
        // Deploy flashloan implementation
        AAVEFlashloan impl = new AAVEFlashloan();
        
        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            AAVEFlashloan.initialize.selector,
            owner,
            address(pool),
            FEE_BPS,
            MIN_PROFIT_BPS
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        flashloan = AAVEFlashloan(address(proxy));
        
        // Deploy workflows
        workflow = new MockWorkflow(address(token), 10150); // 1.5% profit
        failingWorkflow = new FailingWorkflow();
        
        // Setup: mint tokens to pool for flashloan
        token.mint(address(pool), 1000000e18);
    }
    
    function test_Initialization() public view {
        assertEq(flashloan.owner(), owner);
        assertEq(flashloan.feeBps(), FEE_BPS);
        assertEq(flashloan.minProfitBps(), MIN_PROFIT_BPS);
        assertEq(address(flashloan.pool()), address(pool));
    }
    
    function test_ExecuteFlashloan_Success() public {
        vm.startPrank(user);
        
        // Prepare workflow data
        bytes memory workflowData = abi.encode(address(token));
        
        // Execute flashloan
        flashloan.executeFlashloan(
            address(token),
            FLASHLOAN_AMOUNT,
            address(workflow),
            workflowData
        );
        
        vm.stopPrank();
        
        // Verify: user should receive profit (minus fee)
        // Profit = 1000 * 1.015 = 1015, so 15 tokens profit
        // Fee = 15 * 0.005 = 0.075 tokens
        // User gets = 15 - 0.075 = 14.925 tokens
        uint256 userBalance = token.balanceOf(user);
        assertGt(userBalance, 0, "User should receive profit");
    }
    
    function test_ExecuteFlashloan_RevertsIfPaused() public {
        vm.prank(owner);
        flashloan.pause();
        
        vm.prank(user);
        vm.expectRevert();
        flashloan.executeFlashloan(
            address(token),
            FLASHLOAN_AMOUNT,
            address(workflow),
            ""
        );
    }
    
    function test_ExecuteFlashloan_RevertsIfInvalidToken() public {
        vm.prank(user);
        vm.expectRevert();
        flashloan.executeFlashloan(
            address(0),
            FLASHLOAN_AMOUNT,
            address(workflow),
            ""
        );
    }
    
    function test_ExecuteFlashloan_RevertsIfInvalidAmount() public {
        vm.prank(user);
        vm.expectRevert();
        flashloan.executeFlashloan(
            address(token),
            0,
            address(workflow),
            ""
        );
    }
    
    function test_ExecuteFlashloan_RevertsIfWorkflowFails() public {
        vm.prank(user);
        vm.expectRevert();
        flashloan.executeFlashloan(
            address(token),
            FLASHLOAN_AMOUNT,
            address(failingWorkflow),
            ""
        );
    }
    
    function test_SetFee() public {
        vm.prank(owner);
        flashloan.setFee(100);
        assertEq(flashloan.feeBps(), 100);
    }
    
    function test_SetFee_RevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        flashloan.setFee(100);
    }
    
    function test_SetFee_RevertsIfTooHigh() public {
        vm.prank(owner);
        vm.expectRevert();
        flashloan.setFee(1001); // > MAX_FEE_BPS (1000)
    }
    
    function test_SetMinProfit() public {
        vm.prank(owner);
        flashloan.setMinProfit(20);
        assertEq(flashloan.minProfitBps(), 20);
    }
    
    function test_PauseUnpause() public {
        vm.prank(owner);
        flashloan.pause();
        assertTrue(flashloan.paused());
        
        vm.prank(owner);
        flashloan.unpause();
        assertFalse(flashloan.paused());
    }
    
    function test_WithdrawFees() public {
        // First execute a successful flashloan to generate fees
        vm.startPrank(user);
        bytes memory workflowData = abi.encode(address(token));
        flashloan.executeFlashloan(
            address(token),
            FLASHLOAN_AMOUNT,
            address(workflow),
            workflowData
        );
        vm.stopPrank();
        
        // Check fees collected
        uint256 feesBefore = token.balanceOf(address(flashloan));
        assertGt(feesBefore, 0, "Fees should be collected");
        
        // Withdraw fees
        vm.prank(owner);
        flashloan.withdrawFees(address(token), feeRecipient);
        
        uint256 feesAfter = token.balanceOf(address(flashloan));
        assertEq(feesAfter, 0, "Fees should be withdrawn");
        assertGt(token.balanceOf(feeRecipient), 0, "Fee recipient should receive fees");
    }
    
    function test_SetPool() public {
        MockAAVEPool newPool = new MockAAVEPool();
        vm.prank(owner);
        flashloan.setPool(address(newPool));
        assertEq(address(flashloan.pool()), address(newPool));
    }
}

