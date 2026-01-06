// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../src/interfaces/IPool.sol";
import "../../src/interfaces/IFlashLoanReceiver.sol";
import "../../src/interfaces/IERC20.sol";

contract MockAAVEPool is IPool {
    uint256 public constant PREMIUM_BPS = 9; // 0.09% premium
    
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata /* modes */,
        address onBehalfOf,
        bytes calldata params,
        uint16 /* referralCode */
    ) external override {
        require(assets.length == amounts.length, "Invalid arrays");
        
        // Transfer tokens to receiver
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).transfer(receiverAddress, amounts[i]);
        }
        
        // Calculate premiums
        uint256[] memory premiums = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            premiums[i] = (amounts[i] * PREMIUM_BPS) / 10000;
        }
        
        // Call receiver's executeOperation
        require(
            IFlashLoanReceiver(receiverAddress).executeOperation(
                assets,
                amounts,
                premiums,
                onBehalfOf,
                params
            ),
            "Flashloan execution failed"
        );
        
        // Collect repayment + premium
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).transferFrom(
                receiverAddress,
                address(this),
                amounts[i] + premiums[i]
            );
        }
    }
}

