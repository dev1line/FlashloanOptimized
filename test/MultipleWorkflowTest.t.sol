// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AAVEFlashloan} from "../src/AAVEFlashloan.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAAVEPool} from "./mocks/MockAAVEPool.sol";
import {MockWorkflow} from "./mocks/MockWorkflow.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/**
 * @title MultipleWorkflowTest
 * @notice Test multiple workflows in sequence - the correct implementation
 */
contract MultipleWorkflowTest is Test {
    AAVEFlashloan public flashloan;
    MockAAVEPool public pool;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public tokenC;

    address public owner = address(0x1);
    address public user = address(0x2);

    uint256 public constant FLASHLOAN_AMOUNT = 1000e18;
    uint256 public constant FEE_BPS = 50; // 0.5%
    uint256 public constant MIN_PROFIT_BPS = 10; // 0.1%

    function setUp() public {
        // Deploy tokens
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        tokenC = new MockERC20("Token C", "TKC", 18);

        // Deploy mock AAVE pool
        pool = new MockAAVEPool();
        tokenA.mint(address(pool), 1000000e18);

        // Deploy flashloan implementation
        AAVEFlashloan impl = new AAVEFlashloan();
        bytes memory initData =
            abi.encodeWithSelector(AAVEFlashloan.initialize.selector, owner, address(pool), FEE_BPS, MIN_PROFIT_BPS);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        flashloan = AAVEFlashloan(address(proxy));
    }

    function test_MultipleWorkflows_Chain() public {
        // Create workflows for chain: A -> B -> C -> A
        // Each workflow has 1% output multiplier (10100/10000)
        MockWorkflow workflowAB = new MockWorkflow(address(tokenB), 10100); // A -> B
        MockWorkflow workflowBC = new MockWorkflow(address(tokenC), 10100); // B -> C
        MockWorkflow workflowCA = new MockWorkflow(address(tokenA), 10100); // C -> A

        // Fund workflows with output tokens
        tokenB.mint(address(workflowAB), 1000000e18);
        tokenC.mint(address(workflowBC), 1000000e18);
        tokenA.mint(address(workflowCA), 1000000e18);

        uint256 userBalanceBefore = tokenA.balanceOf(user);

        vm.startPrank(user);

        // Prepare workflow chain
        address[] memory workflows = new address[](3);
        workflows[0] = address(workflowAB);
        workflows[1] = address(workflowBC);
        workflows[2] = address(workflowCA);

        bytes[] memory workflowData = new bytes[](3);
        workflowData[0] = abi.encode(address(tokenB), 0); // A -> B
        workflowData[1] = abi.encode(address(tokenC), 0); // B -> C
        workflowData[2] = abi.encode(address(tokenA), 0); // C -> A (back to borrowed token)

        // Execute flashloan with multiple workflows
        flashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);

        vm.stopPrank();

        // Verify user received profit
        uint256 userBalanceAfter = tokenA.balanceOf(user);
        uint256 profit = userBalanceAfter - userBalanceBefore;

        // Expected: 1000 * 1.01^3 = ~1030.3, profit ~30.3, minus fees
        assertGt(profit, 0, "User should receive profit");
        assertGt(userBalanceAfter, userBalanceBefore, "User balance should increase");
    }

    function test_SingleWorkflow_BackToSameToken() public {
        // Single workflow: A -> A (direct swap back)
        MockWorkflow workflowAA = new MockWorkflow(address(tokenA), 10150); // 1.5% profit
        tokenA.mint(address(workflowAA), 1000000e18);

        uint256 userBalanceBefore = tokenA.balanceOf(user);

        vm.startPrank(user);

        address[] memory workflows = new address[](1);
        workflows[0] = address(workflowAA);

        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0); // A -> A

        flashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);

        vm.stopPrank();

        // Verify user received profit
        uint256 userBalanceAfter = tokenA.balanceOf(user);
        assertGt(userBalanceAfter, userBalanceBefore, "User should receive profit");
    }
}

