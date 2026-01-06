// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./utils/OwnableUpgradeable.sol";
import "./utils/PausableUpgradeable.sol";
import "./utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IFlashloanWorkflow.sol";
import "./interfaces/IERC20.sol";

/**
 * @title FlashloanBase
 * @notice Base contract for flashloan operations with upgradability, security, and custom workflow support
 */
abstract contract FlashloanBase is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /// @notice Fee percentage in basis points (1 basis point = 0.01%)
    uint256 public feeBps;

    /// @notice Maximum fee percentage (1000 = 10%)
    uint256 public constant MAX_FEE_BPS = 1000;

    /// @notice Minimum profit required for successful execution (in basis points)
    uint256 public minProfitBps;

    /// @notice Mapping to track active flashloan operations
    mapping(bytes32 => bool) public activeFlashloans;

    /// @notice Events
    event FlashloanExecuted(
        address indexed user, address indexed token, uint256 amount, bool success, uint256 profit, uint256 fee
    );

    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event MinProfitUpdated(uint256 oldMinProfit, uint256 newMinProfit);
    event WorkflowExecuted(address indexed workflow, address indexed token, uint256 amount, bool success);

    /// @notice Custom errors
    error InvalidAmount();
    error InvalidToken();
    error InvalidWorkflow();
    error InsufficientProfit();
    error FlashloanFailed();
    error RepaymentFailed();
    error WorkflowExecutionFailed();
    error FeeTooHigh();
    error InvalidFee();

    /**
     * @notice Initialize the contract
     * @param _owner The owner of the contract
     * @param _feeBps Initial fee in basis points
     * @param _minProfitBps Minimum profit required in basis points
     */
    function __FlashloanBase_init(address _owner, uint256 _feeBps, uint256 _minProfitBps) internal onlyInitializing {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();

        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        feeBps = _feeBps;
        minProfitBps = _minProfitBps;
    }

    /**
     * @notice Set the fee percentage
     * @param _feeBps New fee in basis points
     */
    function setFee(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        uint256 oldFee = feeBps;
        feeBps = _feeBps;
        emit FeeUpdated(oldFee, _feeBps);
    }

    /**
     * @notice Set the minimum profit required
     * @param _minProfitBps Minimum profit in basis points
     */
    function setMinProfit(uint256 _minProfitBps) external onlyOwner {
        uint256 oldMinProfit = minProfitBps;
        minProfitBps = _minProfitBps;
        emit MinProfitUpdated(oldMinProfit, _minProfitBps);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Execute custom workflow
     * @param workflow The workflow contract to execute
     * @param token The token address
     * @param amount The amount of tokens
     * @param data Custom data for the workflow
     * @return success Whether the workflow succeeded
     * @return profit The profit made
     */
    function _executeWorkflow(address workflow, address token, uint256 amount, bytes memory data)
        internal
        returns (bool success, uint256 profit)
    {
        if (workflow == address(0)) revert InvalidWorkflow();

        // Execute the workflow
        (success, profit) = IFlashloanWorkflow(workflow).executeWorkflow(token, amount, data);

        emit WorkflowExecuted(workflow, token, amount, success);

        if (!success) revert WorkflowExecutionFailed();
    }

    /**
     * @notice Calculate fee amount
     * @param amount The base amount
     * @return fee The calculated fee
     */
    function _calculateFee(uint256 amount) internal view returns (uint256 fee) {
        fee = (amount * feeBps) / 10000;
    }

    /**
     * @notice Validate flashloan parameters
     * @param token The token address
     * @param amount The amount to borrow
     */
    function _validateFlashloanParams(address token, uint256 amount) internal pure {
        if (token == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
    }

    /**
     * @notice Check if profit is sufficient
     * @param profit The profit made
     * @param amount The original amount
     */
    function _validateProfit(uint256 profit, uint256 amount) internal view {
        uint256 minProfit = (amount * minProfitBps) / 10000;
        if (profit < minProfit) revert InsufficientProfit();
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Withdraw fees collected
     * @param token The token to withdraw
     * @param to The address to send fees to
     */
    function withdrawFees(address token, address to) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        if (balance > 0) {
            tokenContract.transfer(to, balance);
        }
    }

    /**
     * @notice Emergency withdraw ETH
     */
    function emergencyWithdraw() external onlyOwner {
        (bool success,) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}
