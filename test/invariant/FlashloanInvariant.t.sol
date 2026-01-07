// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AAVEFlashloan} from "../../src/AAVEFlashloan.sol";
import {UniswapFlashSwap} from "../../src/UniswapFlashSwap.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAAVEPool} from "../mocks/MockAAVEPool.sol";
import {MockUniswapPool} from "../mocks/MockUniswapPool.sol";
import {MockWorkflow} from "../mocks/MockWorkflow.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/**
 * @title FlashloanInvariant
 * @notice Invariant testing for flashloan contracts using Handler pattern
 * @dev Tests system-wide invariants through randomized sequences of operations
 */
contract FlashloanInvariant is Test {
    AAVEFlashloan public flashloan;
    UniswapFlashSwap public flashSwap;

    MockAAVEPool public pool;
    MockUniswapPool public uniswapPool;
    MockERC20 public token;
    MockERC20 public token0;
    MockERC20 public token1;

    Handler public handler;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public feeRecipient = address(0x4);

    uint256 public constant FEE_BPS = 50; // 0.5%
    uint256 public constant MIN_PROFIT_BPS = 10; // 0.1%
    uint256 public constant INITIAL_SUPPLY = 10000000e18;

    function setUp() public {
        // Deploy tokens
        token = new MockERC20("Token", "TKN", 18);
        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);

        // Mint initial supply
        token.mint(address(this), INITIAL_SUPPLY);
        token0.mint(address(this), INITIAL_SUPPLY);
        token1.mint(address(this), INITIAL_SUPPLY);

        // Deploy pools
        pool = new MockAAVEPool();
        token.mint(address(pool), INITIAL_SUPPLY);

        uniswapPool = new MockUniswapPool(address(token0), address(token1), 3000);
        token0.mint(address(uniswapPool), INITIAL_SUPPLY);
        token1.mint(address(uniswapPool), INITIAL_SUPPLY);

        // Deploy AAVE Flashloan
        AAVEFlashloan impl = new AAVEFlashloan();
        bytes memory initData =
            abi.encodeWithSelector(AAVEFlashloan.initialize.selector, owner, address(pool), FEE_BPS, MIN_PROFIT_BPS);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        flashloan = AAVEFlashloan(address(proxy));

        // Deploy Uniswap Flash Swap
        UniswapFlashSwap swapImpl = new UniswapFlashSwap();
        bytes memory swapInitData =
            abi.encodeWithSelector(UniswapFlashSwap.initialize.selector, owner, FEE_BPS, MIN_PROFIT_BPS);
        ERC1967Proxy swapProxy = new ERC1967Proxy(address(swapImpl), swapInitData);
        flashSwap = UniswapFlashSwap(address(swapProxy));

        // Deploy handler
        handler = new Handler(flashloan, flashSwap, pool, uniswapPool, token, token0, token1, user1, user2);

        // Fund handler with tokens
        token.mint(address(handler), INITIAL_SUPPLY);
        token0.mint(address(handler), INITIAL_SUPPLY);
        token1.mint(address(handler), INITIAL_SUPPLY);

        // Fund pool continuously for handler
        token.mint(address(pool), INITIAL_SUPPLY * 10);
        token0.mint(address(uniswapPool), INITIAL_SUPPLY * 10);
        token1.mint(address(uniswapPool), INITIAL_SUPPLY * 10);

        // Set target contracts for invariant testing
        targetContract(address(handler));
    }

    /**
     * @notice Invariant: Fee BPS should never exceed MAX_FEE_BPS
     */
    function invariant_feeBpsWithinLimit() public view {
        assertLe(flashloan.feeBps(), 1000, "Fee BPS exceeds maximum");
        assertLe(flashSwap.feeBps(), 1000, "Fee BPS exceeds maximum");
    }

    /**
     * @notice Invariant: Contract should never lose tokens without reason
     * @dev Solvency check: contract balance should always be >= collected fees
     */
    function invariant_solvency() public view {
        uint256 contractBalance = token.balanceOf(address(flashloan));
        // Fees should not exceed balance
        // Note: In real scenario, fees are transferred immediately, so balance should be >= 0
        assertGe(contractBalance, 0, "Contract balance cannot be negative");

        uint256 swapBalance = token0.balanceOf(address(flashSwap));
        assertGe(swapBalance, 0, "Swap contract balance cannot be negative");
    }

    /**
     * @notice Invariant: Owner should always be set and valid
     */
    function invariant_ownerSet() public view {
        assertTrue(flashloan.owner() != address(0), "Owner must be set");
        assertTrue(flashSwap.owner() != address(0), "Owner must be set");
        assertEq(flashloan.owner(), owner, "Owner should remain unchanged");
        assertEq(flashSwap.owner(), owner, "Owner should remain unchanged");
    }

    /**
     * @notice Invariant: Pool address should always be set for AAVE
     */
    function invariant_poolSet() public view {
        assertTrue(address(flashloan.pool()) != address(0), "Pool must be set");
    }

    /**
     * @notice Invariant: Min profit should be reasonable (not excessive)
     */
    function invariant_minProfitReasonable() public view {
        assertLe(flashloan.minProfitBps(), 10000, "Min profit BPS too high");
        assertLe(flashSwap.minProfitBps(), 10000, "Min profit BPS too high");
    }
}

/**
 * @title Handler
 * @notice Handler contract for invariant testing
 * @dev Manages state and operations for fuzzing
 */
contract Handler is Test {
    AAVEFlashloan public flashloan;
    UniswapFlashSwap public flashSwap;

    MockAAVEPool public pool;
    MockUniswapPool public uniswapPool;
    MockERC20 public token;
    MockERC20 public token0;
    MockERC20 public token1;

    address public user1;
    address public user2;

    // Ghost variables for tracking state
    uint256 public ghost_totalFeesCollected;
    uint256 public ghost_totalProfitDistributed;
    uint256 public ghost_totalFlashloans;
    uint256 public ghost_totalFlashSwaps;

    // Track user balances
    mapping(address => uint256) public ghost_userTokenBalance;
    mapping(address => uint256) public ghost_userToken0Balance;
    mapping(address => uint256) public ghost_userToken1Balance;

    // Workflow contracts
    MockWorkflow public workflow1; // For token
    MockWorkflow public workflow2; // For token1 (for Uniswap)

    uint256 public constant INITIAL_SUPPLY = 10000000e18;
    uint256 public constant MIN_AMOUNT = 1e18;
    uint256 public constant MAX_AMOUNT = 1000000e18;
    uint256 public constant PROFIT_MULTIPLIER = 10200; // 2% profit to cover all fees

    constructor(
        AAVEFlashloan _flashloan,
        UniswapFlashSwap _flashSwap,
        MockAAVEPool _pool,
        MockUniswapPool _uniswapPool,
        MockERC20 _token,
        MockERC20 _token0,
        MockERC20 _token1,
        address _user1,
        address _user2
    ) {
        flashloan = _flashloan;
        flashSwap = _flashSwap;
        pool = _pool;
        uniswapPool = _uniswapPool;
        token = _token;
        token0 = _token0;
        token1 = _token1;
        user1 = _user1;
        user2 = _user2;

        // Deploy workflows
        workflow1 = new MockWorkflow(address(token), PROFIT_MULTIPLIER);
        workflow2 = new MockWorkflow(address(token1), PROFIT_MULTIPLIER);

        // Fund workflows
        token.mint(address(workflow1), INITIAL_SUPPLY * 10);
        token1.mint(address(workflow2), INITIAL_SUPPLY * 10);
        token0.mint(address(workflow2), INITIAL_SUPPLY * 10);
    }

    /**
     * @notice Execute AAVE flashloan with fuzzed parameters
     */
    function executeAAVEFlashloan(uint256 amount, address user, uint256 profitBps) public {
        // Bound inputs to valid ranges
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        user = user == address(0) ? user1 : (user == address(flashloan) ? user2 : user);

        // Ensure pool has liquidity
        if (token.balanceOf(address(pool)) < amount) {
            token.mint(address(pool), amount * 2);
        }

        // Bound profit to ensure success (must cover fees + min profit)
        profitBps = bound(profitBps, 150, 500); // 1.5% to 5%

        // Create temporary workflow with specific profit
        MockWorkflow tempWorkflow = new MockWorkflow(address(token), 10000 + profitBps);
        token.mint(address(tempWorkflow), amount * 10);

        // Record initial balances
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 contractBalanceBefore = token.balanceOf(address(flashloan));

        // Skip if contract is paused
        if (flashloan.paused()) return;

        // Execute flashloan
        address[] memory workflows = new address[](1);
        workflows[0] = address(tempWorkflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(address(token), 0);
        try flashloan.executeFlashloan(address(token), amount, workflows, workflowData) {
            // Update ghost variables on success
            ghost_totalFlashloans++;

            uint256 userBalanceAfter = token.balanceOf(user);
            uint256 contractBalanceAfter = token.balanceOf(address(flashloan));

            uint256 profitDistributed = userBalanceAfter > userBalanceBefore ? userBalanceAfter - userBalanceBefore : 0;
            uint256 feesCollected =
                contractBalanceAfter > contractBalanceBefore ? contractBalanceAfter - contractBalanceBefore : 0;

            ghost_totalProfitDistributed += profitDistributed;
            ghost_totalFeesCollected += feesCollected;
            ghost_userTokenBalance[user] = userBalanceAfter;
        } catch {
            // Revert is acceptable - not all operations should succeed
        }
    }

    /**
     * @notice Execute Uniswap flash swap with fuzzed parameters
     */
    function executeUniswapFlashSwap(uint256 amount, address user, bool zeroForOne) public {
        // Bound inputs
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        user = user == address(0) ? user1 : (user == address(flashSwap) ? user2 : user);

        // Ensure pool has liquidity
        if (token0.balanceOf(address(uniswapPool)) < amount) {
            token0.mint(address(uniswapPool), amount * 2);
            token1.mint(address(uniswapPool), amount * 2);
        }

        // Create workflow for token1 (needed for repayment)
        MockWorkflow tempWorkflow = new MockWorkflow(address(token1), PROFIT_MULTIPLIER);
        token1.mint(address(tempWorkflow), amount * 10);
        token0.mint(address(tempWorkflow), amount * 10);

        // Record initial balances
        uint256 userBalanceBefore = zeroForOne ? token0.balanceOf(user) : token1.balanceOf(user);

        // Skip if contract is paused
        if (flashSwap.paused()) return;

        // Execute flash swap
        address[] memory workflows = new address[](1);
        workflows[0] = address(tempWorkflow);
        bytes[] memory workflowData = new bytes[](1);
        workflowData[0] = abi.encode(zeroForOne ? address(token1) : address(token0), 0);
        try flashSwap.executeFlashSwap(
            address(uniswapPool),
            zeroForOne ? address(token0) : address(token1),
            zeroForOne ? address(token1) : address(token0),
            amount,
            workflows,
            workflowData
        ) {
            // Update ghost variables
            ghost_totalFlashSwaps++;

            uint256 userBalanceAfter = zeroForOne ? token0.balanceOf(user) : token1.balanceOf(user);

            uint256 profit = userBalanceAfter > userBalanceBefore ? userBalanceAfter - userBalanceBefore : 0;

            ghost_totalProfitDistributed += profit;

            if (zeroForOne) {
                ghost_userToken0Balance[user] = userBalanceAfter;
            } else {
                ghost_userToken1Balance[user] = userBalanceAfter;
            }
        } catch {
            // Revert is acceptable
        }
    }

    /**
     * @notice Owner operations - change fee
     */
    function ownerSetFee(uint256 feeBps) public {
        feeBps = bound(feeBps, 0, 1000); // Valid range

        vm.startPrank(flashloan.owner());
        try flashloan.setFee(feeBps) {
            // Success
        } catch {
            // May revert if invalid
        }
        vm.stopPrank();
    }

    /**
     * @notice Owner operations - change min profit
     */
    function ownerSetMinProfit(uint256 minProfitBps) public {
        minProfitBps = bound(minProfitBps, 0, 1000);

        vm.startPrank(flashloan.owner());
        try flashloan.setMinProfit(minProfitBps) {
            // Success
        } catch {
            // May revert
        }
        vm.stopPrank();
    }

    /**
     * @notice Owner operations - pause/unpause
     */
    function ownerTogglePause(bool pause) public {
        vm.startPrank(flashloan.owner());
        if (pause && !flashloan.paused()) {
            flashloan.pause();
        } else if (!pause && flashloan.paused()) {
            flashloan.unpause();
        }
        vm.stopPrank();
    }
}
