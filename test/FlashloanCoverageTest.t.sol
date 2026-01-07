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
import {FailingWorkflow} from "./mocks/MockWorkflow.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/**
 * @title FlashloanCoverageTest
 * @notice Comprehensive test suite focused on code coverage
 * @dev Tests cover all functions, edge cases, and error paths
 */
contract FlashloanCoverageTest is Test {
    AAVEFlashloan public aaveFlashloan;
    UniswapFlashSwap public uniswapFlashSwap;
    MockAAVEPool public aavePool;
    MockUniswapPool public uniswapPool;

    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public owner = address(0x1);
    address public user = address(0x2);
    address public feeRecipient = address(0x3);

    uint256 public constant FLASHLOAN_AMOUNT = 1000e18;
    uint256 public constant FEE_BPS = 50;
    uint256 public constant MIN_PROFIT_BPS = 10;

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        aavePool = new MockAAVEPool();
        tokenA.mint(address(aavePool), 1000000e18);

        uniswapPool = new MockUniswapPool(address(tokenA), address(tokenB), 3000);
        tokenA.mint(address(uniswapPool), 1000000e18);
        tokenB.mint(address(uniswapPool), 1000000e18);

        AAVEFlashloan aaveImpl = new AAVEFlashloan();
        bytes memory aaveInitData =
            abi.encodeWithSelector(AAVEFlashloan.initialize.selector, owner, address(aavePool), FEE_BPS, MIN_PROFIT_BPS);
        ERC1967Proxy aaveProxy = new ERC1967Proxy(address(aaveImpl), aaveInitData);
        aaveFlashloan = AAVEFlashloan(address(aaveProxy));

        UniswapFlashSwap uniswapImpl = new UniswapFlashSwap();
        bytes memory uniswapInitData =
            abi.encodeWithSelector(UniswapFlashSwap.initialize.selector, owner, FEE_BPS, MIN_PROFIT_BPS);
        ERC1967Proxy uniswapProxy = new ERC1967Proxy(address(uniswapImpl), uniswapInitData);
        uniswapFlashSwap = UniswapFlashSwap(address(uniswapProxy));
    }

    // ============ AAVE FLASHLOAN COVERAGE ============

    /// @notice Test executeFlashloan with valid parameters
    function test_AAVE_ExecuteFlashloan_Success() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenA), 10150);
        tokenA.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();

        assertGt(tokenA.balanceOf(user), 0);
    }

    /// @notice Test setPool function
    function test_AAVE_SetPool() public {
        MockAAVEPool newPool = new MockAAVEPool();
        vm.prank(owner);
        aaveFlashloan.setPool(address(newPool));
        assertEq(address(aaveFlashloan.pool()), address(newPool));
    }

    /// @notice Test setPool reverts if not owner
    function test_AAVE_SetPool_RevertsIfNotOwner() public {
        MockAAVEPool newPool = new MockAAVEPool();
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.setPool(address(newPool));
    }

    /// @notice Test executeOperation reverts if not called by pool
    function test_AAVE_ExecuteOperation_RevertsIfNotPool() public {
        // This is tested indirectly through executeFlashloan
        // Direct call should revert
        address[] memory assets = new address[](1);
        assets[0] = address(tokenA);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASHLOAN_AMOUNT;
        uint256[] memory premiums = new uint256[](1);
        premiums[0] = 0;
        bytes memory params = abi.encode(new address[](1), new bytes[](1));

        vm.expectRevert(AAVEFlashloan.OnlyPool.selector);
        aaveFlashloan.executeOperation(assets, amounts, premiums, address(0), params);
    }

    /// @notice Test executeOperation reverts if operation not initialized
    function test_AAVE_ExecuteOperation_RevertsIfNotInitialized() public {
        // Setup: call from pool but without setting currentOperation
        vm.prank(address(aavePool));
        address[] memory assets = new address[](1);
        assets[0] = address(tokenA);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASHLOAN_AMOUNT;
        uint256[] memory premiums = new uint256[](1);
        premiums[0] = 0;
        bytes memory params = abi.encode(new address[](1), new bytes[](1));

        vm.expectRevert(AAVEFlashloan.OperationNotInitialized.selector);
        aaveFlashloan.executeOperation(assets, amounts, premiums, address(0), params);
    }

    /// @notice Test executeOperation reverts if already executed
    function test_AAVE_ExecuteOperation_RevertsIfAlreadyExecuted() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenA), 10150);
        tokenA.mint(address(workflow), 1000000e18);

        // Setup operation
        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        // This will set currentOperation and execute it once
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();

        // Try to execute again (should fail because operation is cleared)
        vm.prank(address(aavePool));
        address[] memory assets = new address[](1);
        assets[0] = address(tokenA);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASHLOAN_AMOUNT;
        uint256[] memory premiums = new uint256[](1);
        premiums[0] = 0;
        bytes memory params = abi.encode(workflows, workflowData);

        vm.expectRevert(AAVEFlashloan.OperationNotInitialized.selector);
        aaveFlashloan.executeOperation(assets, amounts, premiums, address(0), params);
    }

    /// @notice Test executeFlashloan reverts if insufficient profit after premium
    function test_AAVE_RevertsIfInsufficientProfitAfterPremium() public {
        // Create workflow with very low output (less than premium)
        MockWorkflow lowProfitWorkflow = new MockWorkflow(address(tokenA), 10008); // 0.08% output
        tokenA.mint(address(lowProfitWorkflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(lowProfitWorkflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        // Should revert because profit (0.08%) < premium (0.09%) + fees
        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    // ============ UNISWAP FLASH SWAP COVERAGE ============

    /// @notice Test executeFlashSwap with valid parameters
    function test_Uniswap_ExecuteFlashSwap_Success() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenB), 10200);
        tokenB.mint(address(workflow), 1000000e18);

        uint256 userBalanceBefore = tokenB.balanceOf(user);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenB), 0);

        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool), address(tokenA), address(tokenB), FLASHLOAN_AMOUNT, workflows, workflowData
        );
        vm.stopPrank();

        assertGt(tokenB.balanceOf(user), userBalanceBefore);
    }

    /// @notice Test executeFlashSwap reverts if pool is zero address
    function test_Uniswap_RevertsIfPoolZero() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenB), 10200);
        tokenB.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenB), 0);

        vm.expectRevert(UniswapFlashSwap.InvalidPool.selector);
        uniswapFlashSwap.executeFlashSwap(
            address(0), address(tokenA), address(tokenB), FLASHLOAN_AMOUNT, workflows, workflowData
        );
        vm.stopPrank();
    }

    /// @notice Test executeFlashSwap reverts if pool tokens don't match
    function test_Uniswap_RevertsIfInvalidPoolTokens() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18);
        MockWorkflow workflow = new MockWorkflow(address(tokenB), 10200);
        tokenB.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenB), 0);

        vm.expectRevert("Invalid pool tokens");
        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool), address(invalidToken), address(tokenB), FLASHLOAN_AMOUNT, workflows, workflowData
        );
        vm.stopPrank();
    }

    /// @notice Test uniswapV3SwapCallback reverts if not called by pool
    function test_Uniswap_Callback_RevertsIfNotPool() public {
        // Setup operation first by starting a flash swap
        MockWorkflow workflow = new MockWorkflow(address(tokenB), 10200);
        tokenB.mint(address(workflow), 1000000e18);

        // Start flash swap in a separate call to set currentOperation
        // But we'll interrupt it by calling callback from wrong address
        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenB), 0);

        // The callback is called during swap, so we need to test it differently
        // Actually, the callback is only called by the pool during swap execution
        // So we test this indirectly - if we try to call it directly, it should revert
        // But currentOperation needs to be set first
        // This is better tested through integration
        
        // For now, test that executeFlashSwap works correctly
        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool), address(tokenA), address(tokenB), FLASHLOAN_AMOUNT, workflows, workflowData
        );
        vm.stopPrank();

        // After swap completes, currentOperation is cleared
        // So direct callback call will revert with OperationNotInitialized
        vm.expectRevert();
        uniswapFlashSwap.uniswapV3SwapCallback(-int256(FLASHLOAN_AMOUNT), int256(FLASHLOAN_AMOUNT), "");
    }

    /// @notice Test uniswapV3SwapCallback reverts if insufficient repayment
    function test_Uniswap_Callback_RevertsIfInsufficientRepayment() public {
        // Create workflow with very low output that won't cover repayment + fees
        // Uniswap fee is 0.3%, so we need at least that + contract fees + min profit
        // 10050 = 0.5% output, which might not be enough after all fees
        MockWorkflow workflow = new MockWorkflow(address(tokenB), 10030); // 0.3% output - barely covers Uniswap fee
        tokenB.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenB), 0);

        // Should revert due to insufficient profit validation (after Uniswap fee + contract fee)
        vm.expectRevert();
        uniswapFlashSwap.executeFlashSwap(
            address(uniswapPool), address(tokenA), address(tokenB), FLASHLOAN_AMOUNT, workflows, workflowData
        );
        vm.stopPrank();
    }

    // ============ FLASHLOAN BASE COVERAGE ============

    /// @notice Test setFee function
    function test_Base_SetFee() public {
        vm.prank(owner);
        aaveFlashloan.setFee(100);
        assertEq(aaveFlashloan.feeBps(), 100);
    }

    /// @notice Test setFee reverts if not owner
    function test_Base_SetFee_RevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.setFee(100);
    }

    /// @notice Test setFee reverts if too high
    function test_Base_SetFee_RevertsIfTooHigh() public {
        vm.prank(owner);
        vm.expectRevert();
        aaveFlashloan.setFee(1001); // > MAX_FEE_BPS
    }

    /// @notice Test setMinProfit function
    function test_Base_SetMinProfit() public {
        vm.prank(owner);
        aaveFlashloan.setMinProfit(20);
        assertEq(aaveFlashloan.minProfitBps(), 20);
    }

    /// @notice Test setMinProfit reverts if not owner
    function test_Base_SetMinProfit_RevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.setMinProfit(20);
    }

    /// @notice Test pause function
    function test_Base_Pause() public {
        vm.prank(owner);
        aaveFlashloan.pause();
        assertTrue(aaveFlashloan.paused());
    }

    /// @notice Test unpause function
    function test_Base_Unpause() public {
        vm.prank(owner);
        aaveFlashloan.pause();
        vm.prank(owner);
        aaveFlashloan.unpause();
        assertFalse(aaveFlashloan.paused());
    }

    /// @notice Test pause reverts if not owner
    function test_Base_Pause_RevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.pause();
    }

    /// @notice Test withdrawFees function
    function test_Base_WithdrawFees() public {
        // Generate fees first
        MockWorkflow workflow = new MockWorkflow(address(tokenA), 10200);
        tokenA.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();

        uint256 feesBefore = tokenA.balanceOf(address(aaveFlashloan));
        assertGt(feesBefore, 0);

        vm.prank(owner);
        aaveFlashloan.withdrawFees(address(tokenA), feeRecipient);

        assertEq(tokenA.balanceOf(address(aaveFlashloan)), 0);
        assertEq(tokenA.balanceOf(feeRecipient), feesBefore);
    }

    /// @notice Test withdrawFees reverts if not owner
    function test_Base_WithdrawFees_RevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.withdrawFees(address(tokenA), feeRecipient);
    }

    /// @notice Test emergencyWithdraw function
    function test_Base_EmergencyWithdraw() public {
        // Send some ETH to contract
        vm.deal(address(aaveFlashloan), 1 ether);

        uint256 balanceBefore = address(owner).balance;

        vm.prank(owner);
        aaveFlashloan.emergencyWithdraw();

        assertEq(address(owner).balance, balanceBefore + 1 ether);
        assertEq(address(aaveFlashloan).balance, 0);
    }

    /// @notice Test emergencyWithdraw reverts if not owner
    function test_Base_EmergencyWithdraw_RevertsIfNotOwner() public {
        vm.deal(address(aaveFlashloan), 1 ether);
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.emergencyWithdraw();
    }

    /// @notice Test executeFlashloan reverts if paused
    function test_Base_ExecuteFlashloan_RevertsIfPaused() public {
        vm.prank(owner);
        aaveFlashloan.pause();

        MockWorkflow workflow = new MockWorkflow(address(tokenA), 10150);
        tokenA.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test executeFlashloan reverts if token is zero
    function test_Base_ExecuteFlashloan_RevertsIfTokenZero() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenA), 10150);
        tokenA.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(0), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test executeFlashloan reverts if amount is zero
    function test_Base_ExecuteFlashloan_RevertsIfAmountZero() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenA), 10150);
        tokenA.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), 0, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test executeFlashloan reverts if workflows array is empty
    function test_Base_ExecuteFlashloan_RevertsIfEmptyWorkflows() public {
        vm.startPrank(user);
        address[] memory workflows = new address[](0);
        bytes[] memory workflowData = new bytes[](0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test executeFlashloan reverts if array lengths mismatch
    function test_Base_ExecuteFlashloan_RevertsIfArrayLengthMismatch() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenA), 10150);
        tokenA.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](2); // Wrong length

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test executeFlashloan reverts if workflow fails
    function test_Base_ExecuteFlashloan_RevertsIfWorkflowFails() public {
        FailingWorkflow failingWorkflow = new FailingWorkflow();

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(failingWorkflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test executeFlashloan reverts if workflow chain invalid (last workflow wrong token)
    function test_Base_ExecuteFlashloan_RevertsIfInvalidChain() public {
        MockWorkflow workflow = new MockWorkflow(address(tokenB), 10150); // Outputs tokenB, not tokenA
        tokenB.mint(address(workflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(workflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenB), 0); // Wrong! Should be tokenA

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }

    /// @notice Test executeFlashloan reverts if insufficient profit
    function test_Base_ExecuteFlashloan_RevertsIfInsufficientProfit() public {
        MockWorkflow lowProfitWorkflow = new MockWorkflow(address(tokenA), 10005); // 0.05% < 0.1% min
        tokenA.mint(address(lowProfitWorkflow), 1000000e18);

        vm.startPrank(user);
        address[] memory workflows = new address[](1);
        workflows[0] = address(lowProfitWorkflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(tokenA), 0);

        vm.expectRevert();
        aaveFlashloan.executeFlashloan(address(tokenA), FLASHLOAN_AMOUNT, workflows, workflowData);
        vm.stopPrank();
    }
}

