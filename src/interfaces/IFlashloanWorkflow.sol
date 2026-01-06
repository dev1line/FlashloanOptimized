// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IFlashloanWorkflow
 * @notice Interface for custom flashloan workflow execution
 */
interface IFlashloanWorkflow {
    /**
     * @notice Execute custom trading workflow with flashloaned funds
     * @param token The address of the token that was flashloaned
     * @param amount The amount of tokens flashloaned
     * @param data Custom data for the workflow execution
     * @return success Whether the workflow executed successfully
     * @return profit The profit made from the workflow (if any)
     */
    function executeWorkflow(
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, uint256 profit);
}

