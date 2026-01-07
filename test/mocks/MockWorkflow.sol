// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/interfaces/IFlashloanWorkflow.sol";
import "../../src/interfaces/IERC20.sol";
import "./MockERC20.sol";

/**
 * @title MockWorkflow
 * @notice Mock workflow for testing - simulates profitable trade
 */
contract MockWorkflow is IFlashloanWorkflow {
    address public tokenOut;
    uint256 public profitMultiplier; // Basis points (10000 = 1x, 10100 = 1.01x)

    event WorkflowExecuted(address tokenIn, uint256 amountIn, uint256 profit);

    constructor(address _tokenOut, uint256 _profitMultiplier) {
        tokenOut = _tokenOut;
        profitMultiplier = _profitMultiplier;
    }

    function executeWorkflow(
        address token,
        uint256 amount,
        bytes calldata /* data */
    )
        external
        override
        returns (bool success, uint256 profit)
    {
        // Simulate swap: receive tokenOut with profit

        // Calculate output amount (with profit)
        uint256 outputAmount = (amount * profitMultiplier) / 10000;

        // The flashloan contract already has the input tokens
        // We just need to provide the output tokens (with profit)
        // In a real scenario, we would swap via a DEX

        // If tokenOut is the same as tokenIn, we need to mint more tokens
        if (token == tokenOut) {
            // Mint additional tokens to simulate profit
            MockERC20 mockToken = MockERC20(token);
            mockToken.mint(msg.sender, outputAmount);
        } else {
            // Different tokens - provide tokenOut to caller for repayment
            // For Uniswap flash swap: caller needs tokenOut to repay pool
            // The repayment amount includes Uniswap fees (typically 0.3% = 3000/1000000)
            // We need to mint enough tokenOut to cover repayment + buffer

            // Calculate repayment amount with Uniswap fee (0.3% = 3000 bps)
            // For Uniswap V3: repayment = amount * (1 + fee/1000000)
            // We use 1% buffer (10100/10000) to ensure we have enough
            // This covers the 0.3% fee (3000/1000000 = 0.003 = 0.3%) with extra margin
            uint256 repaymentAmount = amount;
            uint256 repaymentWithFee = (repaymentAmount * 10100) / 10000; // 1% buffer covers 0.3% fee + margin

            // Mint tokenOut for repayment
            MockERC20 mockOutToken = MockERC20(tokenOut);
            mockOutToken.mint(msg.sender, repaymentWithFee);

            // Calculate and mint profit in original token (tokenIn)
            // Profit = (outputAmount - amount) in tokenIn terms
            // outputAmount = amount * profitMultiplier / 10000
            // This profit needs to cover: contract fee + min profit requirement + Uniswap fee overhead
            uint256 profitAmount = outputAmount > amount ? outputAmount - amount : 0;
            if (profitAmount > 0) {
                MockERC20 mockInToken = MockERC20(token);
                mockInToken.mint(msg.sender, profitAmount);
            }
        }

        // Calculate profit in input token terms
        if (outputAmount > amount) {
            profit = outputAmount - amount;
            success = true;
        } else {
            profit = 0;
            success = false;
        }

        emit WorkflowExecuted(token, amount, profit);
    }

    // Helper to mint tokens for testing
    function mintTokens(address token, uint256 amount) external {
        IERC20(token).transfer(msg.sender, amount);
    }
}

/**
 * @title FailingWorkflow
 * @notice Mock workflow that always fails
 */
contract FailingWorkflow is IFlashloanWorkflow {
    function executeWorkflow(address, uint256, bytes calldata) external pure override returns (bool, uint256) {
        return (false, 0);
    }
}
