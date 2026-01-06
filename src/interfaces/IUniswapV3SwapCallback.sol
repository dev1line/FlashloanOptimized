// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IUniswapV3SwapCallback
 * @notice Callback interface for Uniswap V3 swaps
 */
interface IUniswapV3SwapCallback {
    /**
     * @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
     * @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token0 to the pool.
     * @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
     * the end of the swap. If positive, the callback must send that amount of token1 to the pool.
     * @param data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
     */
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

