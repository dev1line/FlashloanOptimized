// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./FlashloanBase.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IFlashLoanReceiver.sol";
import "./interfaces/IERC20.sol";

/**
 * @title AAVEFlashloan
 * @notice Contract for executing flashloans from AAVE with custom workflows
 */
contract AAVEFlashloan is FlashloanBase, IFlashLoanReceiver {
    /// @notice AAVE Pool address
    IPool public pool;
    
    /// @notice Flashloan operation data
    struct FlashloanOperation {
        address user;
        address token;
        uint256 amount;
        address workflow;
        bytes workflowData;
        bool executed;
    }
    
    /// @notice Current flashloan operation
    FlashloanOperation public currentOperation;
    
    /// @notice Custom errors
    error OnlyPool();
    error OperationNotInitialized();
    error OperationAlreadyExecuted();
    
    /**
     * @notice Initialize the contract
     * @param _owner The owner of the contract
     * @param _pool AAVE Pool address
     * @param _feeBps Initial fee in basis points
     * @param _minProfitBps Minimum profit required in basis points
     */
    function initialize(
        address _owner,
        address _pool,
        uint256 _feeBps,
        uint256 _minProfitBps
    ) external initializer {
        __FlashloanBase_init(_owner, _feeBps, _minProfitBps);
        pool = IPool(_pool);
    }
    
    /**
     * @notice Execute flashloan from AAVE
     * @param token The token to borrow
     * @param amount The amount to borrow
     * @param workflow The workflow contract to execute
     * @param workflowData Custom data for the workflow
     */
    function executeFlashloan(
        address token,
        uint256 amount,
        address workflow,
        bytes calldata workflowData
    ) external nonReentrant whenNotPaused {
        _validateFlashloanParams(token, amount);
        
        // Store operation data
        currentOperation = FlashloanOperation({
            user: msg.sender,
            token: token,
            amount: amount,
            workflow: workflow,
            workflowData: workflowData,
            executed: false
        });
        
        // Prepare flashloan parameters
        address[] memory assets = new address[](1);
        assets[0] = token;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // Don't open debt, just revert if funds can't be transferred
        
        bytes memory params = abi.encode(workflow, workflowData);
        
        // Execute flashloan
        pool.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            params,
            0 // referral code
        );
        
        // Clear operation data
        delete currentOperation;
    }
    
    /**
     * @notice Callback function called by AAVE Pool after flashloan
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts of the assets being flash-borrowed
     * @param premiums The fee of each asset being flash-borrowed
     * @param params Variadic packed params
     * @return True if execution succeeds
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address /* initiator */,
        bytes calldata params
    ) external override returns (bool) {
        // Only AAVE Pool can call this
        if (msg.sender != address(pool)) revert OnlyPool();
        
        // Verify operation is initialized
        if (currentOperation.user == address(0)) revert OperationNotInitialized();
        if (currentOperation.executed) revert OperationAlreadyExecuted();
        
        address token = assets[0];
        uint256 amount = amounts[0];
        uint256 premium = premiums[0];
        
        // Mark as executed
        currentOperation.executed = true;
        
        // Decode workflow parameters
        (address workflow, bytes memory workflowDataBytes) = abi.decode(params, (address, bytes));
        
        // Execute custom workflow
        (bool workflowSuccess, uint256 profit) = _executeWorkflow(
            workflow,
            token,
            amount,
            workflowDataBytes
        );
        
        // Calculate total amount to repay (principal + premium)
        uint256 totalRepayAmount = amount + premium;
        
        // Calculate fee
        uint256 fee = _calculateFee(profit);
        
        // Validate profit after fees
        uint256 netProfit = profit > fee ? profit - fee : 0;
        _validateProfit(netProfit, amount);
        
        // Approve repayment to AAVE Pool
        IERC20(token).approve(address(pool), totalRepayAmount);
        
        // Transfer profit (after fee) to user if any
        if (netProfit > 0) {
            IERC20(token).transfer(currentOperation.user, netProfit);
        }
        
        // Transfer fee to contract
        if (fee > 0) {
            IERC20(token).transfer(address(this), fee);
        }
        
        // Emit event
        emit FlashloanExecuted(
            currentOperation.user,
            token,
            amount,
            workflowSuccess,
            netProfit,
            fee
        );
        
        return true;
    }
    
    /**
     * @notice Update AAVE Pool address
     * @param _pool New pool address
     */
    function setPool(address _pool) external onlyOwner {
        pool = IPool(_pool);
    }
}

