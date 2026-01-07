// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/interfaces/IUniswapV3Pool.sol";
import "../../src/interfaces/IUniswapV3SwapCallback.sol";
import "../../src/interfaces/IERC20.sol";

contract MockUniswapPool is IUniswapV3Pool {
    address public token0;
    address public token1;
    uint24 public fee;

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160, /* sqrtPriceLimitX96 */
        bytes calldata data
    ) external override returns (int256 amount0, int256 amount1) {
        // Simplified swap logic for testing with proper fee calculation
        // Uniswap V3 fee is in basis points of 1000000 (fee = 3000 means 0.3%)
        if (zeroForOne) {
            // Selling token0, buying token1
            uint256 amount0Out = uint256(-amountSpecified);
            IERC20(token0).transfer(recipient, amount0Out);

            // Calculate amount1 to pay back: amount0Out * (1 + fee/1000000)
            // This simulates the fee that needs to be paid to the pool
            uint256 amount1In = (amount0Out * (1000000 + fee)) / 1000000;

            // Call callback first (flashloan pattern)
            // Callback should approve and provide tokens
            IUniswapV3SwapCallback(recipient).uniswapV3SwapCallback(-int256(amount0Out), int256(amount1In), data);

            // Then collect payment (callback should have approved)
            // Note: In real Uniswap, the callback must provide tokens via transfer
            // For testing, we check allowance and transferFrom
            uint256 allowance = IERC20(token1).allowance(recipient, address(this));
            if (allowance >= amount1In) {
                IERC20(token1).transferFrom(recipient, address(this), amount1In);
            } else {
                // Fallback: try direct transfer if recipient has balance
                uint256 balance = IERC20(token1).balanceOf(recipient);
                if (balance >= amount1In) {
                    IERC20(token1).transferFrom(recipient, address(this), amount1In);
                } else {
                    require(false, "Insufficient allowance");
                }
            }

            return (-int256(amount0Out), int256(amount1In));
        } else {
            // Selling token1, buying token0
            uint256 amount1Out = uint256(-amountSpecified);
            IERC20(token1).transfer(recipient, amount1Out);

            // Calculate amount0 to pay back: amount1Out * (1 + fee/1000000)
            uint256 amount0In = (amount1Out * (1000000 + fee)) / 1000000;

            // Call callback first (flashloan pattern)
            // Callback should approve and provide tokens
            IUniswapV3SwapCallback(recipient).uniswapV3SwapCallback(int256(amount0In), -int256(amount1Out), data);

            // Then collect payment (callback should have approved)
            // Note: In real Uniswap, the callback must provide tokens via transfer
            // For testing, we check allowance and transferFrom
            uint256 allowance = IERC20(token0).allowance(recipient, address(this));
            if (allowance >= amount0In) {
                IERC20(token0).transferFrom(recipient, address(this), amount0In);
            } else {
                // Fallback: try direct transfer if recipient has balance
                uint256 balance = IERC20(token0).balanceOf(recipient);
                if (balance >= amount0In) {
                    IERC20(token0).transferFrom(recipient, address(this), amount0In);
                } else {
                    require(false, "Insufficient allowance");
                }
            }

            return (int256(amount0In), -int256(amount1Out));
        }
    }
}
