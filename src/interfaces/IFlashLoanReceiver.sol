// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IFlashLoanReceiver
 * @notice Interface for AAVE flashloan receiver
 */
interface IFlashLoanReceiver {
    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts of the assets being flash-borrowed
     * @param premiums The fee of each asset being flash-borrowed
     * @param initiator The address that initiated the flash loan
     * @param params Variadic packed params to pass to the receiver as extra information
     * @return True if the execution of the operation succeeds, false otherwise
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

