// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IFlashloanWorkflow
 * @notice Interface for custom flashloan workflow execution
 * @dev Each workflow represents a single token swap (tokenIn -> tokenOut)
 */
interface IFlashloanWorkflow {
    /**
     * @notice Execute a single swap workflow
     * @param tokenIn The address of the input token
     * @param amountIn The amount of input tokens
     * @param data Custom data for the workflow execution (should encode tokenOut and swap parameters)
     * @return success Whether the workflow executed successfully
     * @return amountOut The amount of output tokens received
     */
    function executeWorkflow(address tokenIn, uint256 amountIn, bytes calldata data)
        external
        returns (bool success, uint256 amountOut);
}
