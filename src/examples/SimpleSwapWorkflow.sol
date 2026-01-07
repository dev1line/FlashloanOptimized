// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IFlashloanWorkflow.sol";
import "../interfaces/IERC20.sol";

/**
 * @title SimpleSwapWorkflow
 * @notice Example workflow that swaps tokens using a DEX
 */
contract SimpleSwapWorkflow is IFlashloanWorkflow {
    /// @notice DEX router interface (simplified)
    address public router;

    /// @notice Swap function signature
    bytes4 private constant SWAP_SELECTOR = bytes4(keccak256("swap(address,address,uint256,uint256,address)"));

    event SwapExecuted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _router) {
        router = _router;
    }

    /**
     * @notice Execute a single swap workflow (tokenIn -> tokenOut)
     * @param tokenIn The input token address
     * @param amountIn The amount of input tokens
     * @param data Encoded swap parameters: (address tokenOut, uint256 minAmountOut)
     * @return success Whether the swap succeeded
     * @return amountOut The amount of output tokens received
     */
    function executeWorkflow(address tokenIn, uint256 amountIn, bytes calldata data)
        external
        override
        returns (bool success, uint256 amountOut)
    {
        // Decode swap parameters
        (address tokenOut, uint256 minAmountOut) = abi.decode(data, (address, uint256));

        // Approve router to spend input tokens
        IERC20(tokenIn).approve(router, amountIn);

        // Execute swap (simplified - in production, use proper DEX router)
        // This is a placeholder - actual implementation depends on the DEX
        (bool swapSuccess, bytes memory returnData) =
            router.call(abi.encodeWithSelector(SWAP_SELECTOR, tokenIn, tokenOut, amountIn, minAmountOut, address(this)));

        if (!swapSuccess) {
            return (false, 0);
        }

        // Get amount out (simplified)
        amountOut = abi.decode(returnData, (uint256));

        // Check if minimum amount out is met
        if (amountOut >= minAmountOut) {
            success = true;
        } else {
            success = false;
            amountOut = 0;
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
    }
}
