// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/interfaces/IFlashloanWorkflow.sol";
import "../../src/interfaces/IERC20.sol";
import "./MockERC20.sol";

/**
 * @title MockWorkflow
 * @notice Mock workflow for testing - simulates a single token swap
 * @dev Each workflow performs one swap: tokenIn -> tokenOut
 */
contract MockWorkflow is IFlashloanWorkflow {
    address public tokenOut;
    uint256 public outputMultiplier; // Basis points (10000 = 1x, 10100 = 1.01x)

    event WorkflowExecuted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _tokenOut, uint256 _outputMultiplier) {
        tokenOut = _tokenOut;
        outputMultiplier = _outputMultiplier;
    }

    /**
     * @notice Execute a single swap workflow
     * @param tokenIn The input token address
     * @param amountIn The amount of input tokens
     * @param data Should encode (address tokenOut, uint256 minAmountOut) but we use constructor tokenOut
     * @return success Whether the swap succeeded
     * @return amountOut The amount of output tokens received
     */
    function executeWorkflow(address tokenIn, uint256 amountIn, bytes calldata data)
        external
        override
        returns (bool success, uint256 amountOut)
    {
        // Decode expected tokenOut from data (for validation)
        address expectedTokenOut;
        uint256 minAmountOut;
        if (data.length >= 64) {
            (expectedTokenOut, minAmountOut) = abi.decode(data, (address, uint256));
            // Use expectedTokenOut if provided, otherwise use constructor tokenOut
            if (expectedTokenOut != address(0)) {
                tokenOut = expectedTokenOut;
            }
        }

        // Calculate output amount
        amountOut = (amountIn * outputMultiplier) / 10000;

        // Check minimum amount out
        if (amountOut < minAmountOut) {
            return (false, 0);
        }

        // The flashloan contract already has the input tokens
        // We need to provide the output tokens
        // In a real scenario, we would swap via a DEX

        // Mint output tokens to the caller (flashloan contract)
        MockERC20 mockOutToken = MockERC20(tokenOut);
        mockOutToken.mint(msg.sender, amountOut);

        success = true;
        emit WorkflowExecuted(tokenIn, tokenOut, amountIn, amountOut);
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
    function executeWorkflow(address, uint256, bytes calldata) external pure override returns (bool success, uint256 amountOut) {
        return (false, 0);
    }
}
