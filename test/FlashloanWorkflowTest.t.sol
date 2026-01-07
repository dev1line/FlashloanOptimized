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
 * @title FlashloanWorkflowTest
 * @notice Comprehensive tests for the new workflow architecture
 * @dev Tests verify:
 *      - Each workflow is a single swap (tokenIn -> tokenOut)
 *      - Multiple workflows can be chained together
 *      - First workflow's tokenIn = borrowed token
 *      - Last workflow's tokenOut = borrowed token (for repayment)
 *      - Profit is calculated only at the end
 */
contract FlashloanWorkflowTest is Test {
    AAVEFlashloan public aaveFlashloan;
    UniswapFlashSwap public uniswapFlashSwap;
    MockAAVEPool public aavePool;
    MockUniswapPool public uniswapPool;

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

        // Setup AAVE pool
        aavePool = new MockAAVEPool();
        tokenA.mint(address(aavePool), 1000000e18);

        // Setup Uniswap pool (A/B)
        uniswapPool = new MockUniswapPool(address(tokenA), address(tokenB), 3000);
        tokenA.mint(address(uniswapPool), 1000000e18);
        tokenB.mint(address(uniswapPool), 1000000e18);

        // Deploy AAVE Flashloan
        AAVEFlashloan aaveImpl = new AAVEFlashloan();
        bytes memory aaveInitData =
            abi.encodeWithSelector(AAVEFlashloan.initialize.selector, owner, address(aavePool), FEE_BPS, MIN_PROFIT_BPS);
        ERC1967Proxy aaveProxy = new ERC1967Proxy(address(aaveImpl), aaveInitData);
        aaveFlashloan = AAVEFlashloan(address(aaveProxy));

        // Deploy Uniswap Flash Swap
        UniswapFlashSwap uniswapImpl = new UniswapFlashSwap();
        bytes memory uniswapInitData =
            abi.encodeWithSelector(UniswapFlashSwap.initialize.selector, owner, FEE_BPS, MIN_PROFIT_BPS);
        ERC1967Proxy uniswapProxy = new ERC1967Proxy(address(uniswapImpl), uniswapInitData);
        uniswapFlashSwap = UniswapFlashSwap(address(uniswapProxy));
    }

    // ============ AAVE FLASHLOAN TESTS ============

    /// @notice Test single workflow: A -> A (direct swap back)
    function test_AAVE_SingleWorkflow_SameToken() public {
        // Create workflow: A -> A with 1.5% profit
        MockWorkflow workflowAA = new MockWorkflow(address(tokenA), 10150);
        tokenA.mint(address(workflowAA), 1000000e18);

        uint256 userBalanceBefore = tokenA.balanceOf(user);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflowAA);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0); // A -> A

        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();

        // Verify profit
        uint256 userBalanceAfter = tokenA.balanceOf(user);
        uint256 profit = userBalanceAfter - userBalanceBefore;
        assertGt(profit, 0, "User should receive profit");

        // Expected: 1000 * 1.015 = 1015, minus AAVE premium (~9), minus fee, net ~5-6
        assertGt(profit, 0, "Profit should be positive");
    }

    /// @notice Test multiple workflows chained: A -> B -> C -> A
    function test_AAVE_MultipleWorkflows_Chain() public {
        // Create workflow chain: A -> B -> C -> A
        // Each workflow has 1% output multiplier
        MockWorkflow workflowAB = new MockWorkflow(address(tokenB), 10100); // A -> B
        MockWorkflow workflowBC = new MockWorkflow(address(tokenC), 10100); // B -> C
        MockWorkflow workflowCA = new MockWorkflow(address(tokenA), 10100); // C -> A

        // Fund workflows with output tokens
        tokenB.mint(address(workflowAB), 1000000e18);
        tokenC.mint(address(workflowBC), 1000000e18);
        tokenA.mint(address(workflowCA), 1000000e18);

        uint256 userBalanceBefore = tokenA.balanceOf(user);

        vm.startPrank(user);
        address[] memory workflows = new address[](3);
        workflows[0] = address(workflowAB);
        workflows[1] = address(workflowBC);
        workflows[2] = address(workflowCA);

        bytes[] memory workflowData = new bytes[](3);
        workflowData[0] = abi.encode(address(tokenB), 0); // A -> B
        workflowData[1] = abi.encode(address(tokenC), 0); // B -> C
        workflowData[2] = abi.encode(address(tokenA), 0); // C -> A (back to borrowed token)

        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();

        // Verify profit
        uint256 userBalanceAfter = tokenA.balanceOf(user);
        uint256 profit = userBalanceAfter - userBalanceBefore;

        // Expected: 1000 * 1.01^3 = ~1030.3, minus AAVE premium (~9), minus fee, net ~20
        assertGt(profit, 0, "User should receive profit after multiple workflows");
    }

    /// @notice Test that profit is calculated only at the end, not after each workflow
    function test_AAVE_ProfitCalculatedOnlyAtEnd() public {
        // Create workflows with different multipliers
        // Workflow 1: A -> B (0.5% output)
        MockWorkflow workflowAB = new MockWorkflow(address(tokenB), 10050);
        // Workflow 2: B -> A (0.5% output)
        MockWorkflow workflowBA = new MockWorkflow(address(tokenA), 10050);

        tokenB.mint(address(workflowAB), 1000000e18);
        tokenA.mint(address(workflowBA), 1000000e18);

        uint256 userBalanceBefore = tokenA.balanceOf(user);

        vm.startPrank(user);
        address[] memory workflows = new address[](2);
        workflows[0] = address(workflowAB);
        workflows[1] = address(workflowBA);

        bytes[] memory workflowData = new bytes[](2);
        workflowData[0] = abi.encode(address(tokenB), 0);
        workflowData[1] = abi.encode(address(tokenA), 0);

        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();

        // Verify: Even though each workflow has only 0.5% output,
        // the chain should still be profitable if final amount > original + fees
        uint256 userBalanceAfter = tokenA.balanceOf(user);
        uint256 profit = userBalanceAfter - userBalanceBefore;

        // Expected: 1000 * 1.005^2 = ~1010.025, minus fees
        // This should still be profitable
        assertGt(profit, 0, "Chain should be profitable even with small individual profits");
    }

    /// @notice Test that first workflow must start with borrowed token
    function test_AAVE_RevertsIfFirstWorkflowWrongToken() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenB), 10100);
        tokenB.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        // Wrong: workflow expects tokenB as input, but we borrowed tokenA
        workflowData[0] = abi.encode(address(tokenB), 0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test that last workflow must end with borrowed token
    function test_AAVE_RevertsIfLastWorkflowWrongToken() public {
        MockWorkflow workflowAB = new MockWorkflow(address(tokenB), 10100);
        MockWorkflow workflowBC = new MockWorkflow(address(tokenC), 10100);

        tokenB.mint(address(workflowAB), 1000000e18);
        tokenC.mint(address(workflowBC), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](2);
        workflows[0] = address(workflowAB);
        workflows[1] = address(workflowBC);

        bytes[] memory workflowData = new bytes[](2);
        workflowData[0] = abi.encode(address(tokenB), 0);
        // Wrong: last workflow outputs tokenC, but we borrowed tokenA
        workflowData[1] = abi.encode(address(tokenC), 0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    // ============ UNISWAP FLASH SWAP TESTS ============

    /// @notice Test Uniswap flash swap with single workflow: A -> B
    function test_Uniswap_SingleWorkflow() public {
        // Borrow tokenA, must pay back tokenB
        MockWorkflow workflowAB = new MockWorkflow(address(tokenB), 10200); // 2% output
        tokenB.mint(address(workflowAB), 1000000e18);

        // Check balance before: user should have 0 tokenB
        uint256 userBalanceBefore = tokenB.balanceOf(user);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflowAB);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenB), 0); // A -> B (repayment token)

        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool), address(tokenA), address(tokenB), FLASHLOAN_AMOUNT, workflows, workflowData
        );
        vm.stopPrank();

        // User should receive profit in tokenB (repayment token)
        // Profit = (amountOut - repayment) - fees, all in tokenB
        uint256 userBalanceAfter = tokenB.balanceOf(user);
        assertGt(userBalanceAfter, userBalanceBefore, "User should receive profit in tokenB");
    }

    /// @notice Test Uniswap with multiple workflows: A -> B -> C -> B
    function test_Uniswap_MultipleWorkflows() public {
        // Borrow tokenA, must pay back tokenB
        // Chain: A -> B -> C -> B
        MockWorkflow workflowAB = new MockWorkflow(address(tokenB), 10100);
        MockWorkflow workflowBC = new MockWorkflow(address(tokenC), 10100);
        MockWorkflow workflowCB = new MockWorkflow(address(tokenB), 10100);

        tokenB.mint(address(workflowAB), 1000000e18);
        tokenC.mint(address(workflowBC), 1000000e18);
        tokenB.mint(address(workflowCB), 1000000e18);

        // Check balance before: user should have 0 tokenB
        uint256 userBalanceBefore = tokenB.balanceOf(user);

        vm.startPrank(user);
        address[] memory workflows = new address[](3);
        workflows[0] = address(workflowAB);
        workflows[1] = address(workflowBC);
        workflows[2] = address(workflowCB);

        bytes[] memory workflowData = new bytes[](3);
        workflowData[0] = abi.encode(address(tokenB), 0); // A -> B
        workflowData[1] = abi.encode(address(tokenC), 0); // B -> C
        workflowData[2] = abi.encode(address(tokenB), 0); // C -> B (repayment token)

        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool), address(tokenA), address(tokenB), FLASHLOAN_AMOUNT, workflows, workflowData
        );
        vm.stopPrank();

        // User should receive profit in tokenB (repayment token)
        uint256 userBalanceAfter = tokenB.balanceOf(user);
        assertGt(userBalanceAfter, userBalanceBefore, "User should receive profit in tokenB");
    }

    /// @notice Test that Uniswap workflow chain must end with repayment token
    function test_Uniswap_RevertsIfLastWorkflowWrongToken() public {
        MockWorkflow workflowAB = new MockWorkflow(address(tokenB), 10100);
        MockWorkflow workflowBC = new MockWorkflow(address(tokenC), 10100);

        tokenB.mint(address(workflowAB), 1000000e18);
        tokenC.mint(address(workflowBC), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](2);
        workflows[0] = address(workflowAB);
        workflows[1] = address(workflowBC);

        bytes[] memory workflowData = new bytes[](2);
        workflowData[0] = abi.encode(address(tokenB), 0);
        // Wrong: last workflow outputs tokenC, but we need to pay back tokenB
        workflowData[1] = abi.encode(address(tokenC), 0);

        vm.expectRevert();
        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool), address(tokenA), address(tokenB), FLASHLOAN_AMOUNT, workflows, workflowData
        );
        vm.stopPrank();
    }

    // ============ EDGE CASES ============

    /// @notice Test with empty workflows array (should revert)
    function test_RevertsIfEmptyWorkflows() public {
        vm.startPrank(user);
        address[] memory workflows = new address[](0);
        bytes[] memory workflowData = new bytes[](0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test with mismatched array lengths (should revert)
    function test_RevertsIfMismatchedArrayLengths() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenA), 10100);
        tokenA.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](2); // Wrong length

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test that insufficient profit reverts
    function test_RevertsIfInsufficientProfit() public {
        // Create workflow with very low output (below min profit)
        MockWorkflow lowProfitWorkflow = new MockWorkflow(address(tokenA), 10005); // 0.05% output
        tokenA.mint(address(lowProfitWorkflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(lowProfitWorkflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        vm.expectRevert(abi.encodeWithSignature("InsufficientProfit()"));
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }
}
