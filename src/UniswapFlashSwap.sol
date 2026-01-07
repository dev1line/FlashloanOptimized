// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./FlashloanBase.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "./interfaces/IERC20.sol";

/**
 * @title UniswapFlashSwap
 * @notice Contract for executing flash swaps from Uniswap V3 with custom workflows
 */
contract UniswapFlashSwap is FlashloanBase, IUniswapV3SwapCallback {
    /// @notice Flash swap operation data
    struct FlashSwapOperation {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        address pool;
        address[] workflows;
        bytes[] workflowData;
        bool executed;
    }

    /// @notice Current flash swap operation
    FlashSwapOperation public currentOperation;

    /// @notice Custom errors
    error OnlyPool();
    error OperationNotInitialized();
    error OperationAlreadyExecuted();
    error InvalidPool();
    error InsufficientRepayment();

    /**
     * @notice Initialize the contract
     * @param _owner The owner of the contract
     * @param _feeBps Initial fee in basis points
     * @param _minProfitBps Minimum profit required in basis points
     */
    function initialize(address _owner, uint256 _feeBps, uint256 _minProfitBps) external initializer {
        __FlashloanBase_init(_owner, _feeBps, _minProfitBps);
    }

    /**
     * @notice Execute flash swap from Uniswap V3 with multiple workflows
     * @param pool The Uniswap V3 pool address
     * @param tokenIn The token to receive (flashloan)
     * @param tokenOut The token to pay back
     * @param amountIn The amount of tokenIn to receive
     * @param workflows Array of workflow contracts to execute in sequence
     * @param workflowData Array of custom data for each workflow
     * @dev First workflow's tokenIn must be the borrowed token (tokenIn)
     * @dev Last workflow's tokenOut must be the repayment token (tokenOut)
     */
    function executeFlashSwap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address[] calldata workflows,
        bytes[] calldata workflowData
    ) external nonReentrant whenNotPaused {
        _validateFlashloanParams(tokenIn, amountIn);
        if (pool == address(0)) revert InvalidPool();
        if (workflows.length == 0) revert InvalidWorkflow();
        if (workflows.length != workflowData.length) revert InvalidWorkflow();

        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);

        // Verify pool tokens
        address poolToken0 = poolContract.token0();
        address poolToken1 = poolContract.token1();
        require(
            (poolToken0 == tokenIn && poolToken1 == tokenOut) || (poolToken1 == tokenIn && poolToken0 == tokenOut),
            "Invalid pool tokens"
        );

        // Store operation data
        currentOperation = FlashSwapOperation({
            user: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            pool: pool,
            workflows: workflows,
            workflowData: workflowData,
            executed: false
        });

        // Determine swap direction
        bool zeroForOne = tokenIn == poolToken0;

        // Execute flash swap
        // Negative amount means exact output (we want to receive amountIn)
        poolContract.swap(
            address(this),
            zeroForOne,
            -int256(amountIn),
            zeroForOne ? 4295128739 : 1461446703485210103287273052203988822378723970342, // Max price
            abi.encode(workflows, workflowData)
        );

        // Clear operation data
        delete currentOperation;
    }

    /**
     * @notice Callback function called by Uniswap V3 Pool during swap
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive)
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive)
     * @param data Encoded workflow parameters
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Verify operation is initialized
        if (currentOperation.user == address(0)) revert OperationNotInitialized();
        if (currentOperation.executed) revert OperationAlreadyExecuted();

        // Only the pool can call this
        if (msg.sender != currentOperation.pool) revert OnlyPool();

        // Determine which token we received and how much we need to pay back
        address tokenReceived;
        uint256 amountReceived;
        address tokenToPay;
        uint256 amountToPay;

        IUniswapV3Pool poolContract = IUniswapV3Pool(currentOperation.pool);
        address token0 = poolContract.token0();
        address token1 = poolContract.token1();

        // In Uniswap V3 callback:
        // - amount0Delta < 0 means we received token0 (negative delta = we received it)
        // - amount0Delta > 0 means we owe token0 (positive delta = we must pay it)
        // - amount1Delta < 0 means we received token1
        // - amount1Delta > 0 means we owe token1
        if (amount0Delta < 0) {
            // We received token0 (negative delta), need to pay token1
            tokenReceived = token0;
            amountReceived = uint256(-amount0Delta);
            tokenToPay = token1;
            amountToPay = uint256(amount1Delta);
        } else {
            // We received token1 (amount1Delta < 0), need to pay token0
            tokenReceived = token1;
            amountReceived = uint256(-amount1Delta);
            tokenToPay = token0;
            amountToPay = uint256(amount0Delta);
        }

        // Mark as executed
        currentOperation.executed = true;

        // Pre-approve pool for repayment (BEFORE workflow execution)
        // This ensures approval is available when pool checks it after callback returns
        // Use max approval for safety
        IERC20(tokenToPay).approve(currentOperation.pool, type(uint256).max);

        // Decode workflow parameters
        (address[] memory workflows, bytes[] memory workflowDataBytes) = abi.decode(data, (address[], bytes[]));

        // Execute workflows in sequence
        // For Uniswap: first workflow's tokenIn = tokenReceived (borrowed), last workflow's tokenOut = tokenToPay (repayment)
        address currentToken = tokenReceived;
        uint256 currentAmount = amountReceived;

        // Validate first workflow's tokenIn
        if (currentToken != tokenReceived) revert InvalidWorkflowChain();

        for (uint256 i = 0; i < workflows.length; i++) {
            // Decode tokenOut from workflow data
            address tokenOut;
            (tokenOut,) = abi.decode(workflowDataBytes[i], (address, uint256));

            // Validate last workflow's tokenOut
            if (i == workflows.length - 1) {
                // Last workflow's tokenOut must equal tokenToPay (repayment token)
                // Note: For Uniswap, tokenToPay may differ from tokenReceived
                // But we still validate that the chain ends with the correct repayment token
                if (tokenOut != tokenToPay) revert InvalidWorkflowChain();
            }

            // Execute workflow
            (bool success, uint256 amountOut) =
                _executeWorkflow(workflows[i], currentToken, currentAmount, workflowDataBytes[i]);
            if (!success) revert WorkflowExecutionFailed();

            currentToken = tokenOut;
            currentAmount = amountOut;
        }

        // Final token must be tokenToPay (repayment token)
        if (currentToken != tokenToPay) revert InvalidWorkflowChain();

        // Check if we have enough tokens to repay
        if (currentAmount < amountToPay) revert InsufficientRepayment();

        // Process profit and transfers
        _processUniswapProfitAndEmit(currentAmount, amountToPay, amountReceived, tokenReceived, tokenToPay);
    }

    /**
     * @notice Process profit calculation and transfers for Uniswap flash swap
     * @param finalAmount Final amount of tokenToPay after workflows
     * @param amountToPay Amount needed to repay the pool
     * @param amountReceived Original amount received from pool
     * @param tokenReceived Token received from pool
     * @param tokenToPay Token to pay back to pool
     */
    function _processUniswapProfitAndEmit(
        uint256 finalAmount,
        uint256 amountToPay,
        uint256 amountReceived,
        address tokenReceived,
        address tokenToPay
    ) internal {
        uint256 profit = finalAmount - amountToPay;
        uint256 fee = _calculateFee(profit);
        uint256 netProfit = profit > fee ? profit - fee : 0;
        _validateProfit(netProfit, amountReceived);

        address user = currentOperation.user;
        if (profit > fee) {
            IERC20(tokenToPay).transfer(user, profit - fee);
            if (fee > 0) {
                IERC20(tokenToPay).transfer(address(this), fee);
            }
        }

        emit FlashloanExecuted(user, tokenReceived, amountReceived, true, netProfit, fee);
    }
}
