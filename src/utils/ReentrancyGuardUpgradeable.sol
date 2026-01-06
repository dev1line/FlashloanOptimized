// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/**
 * @title ReentrancyGuardUpgradeable
 * @notice Upgradeable version of ReentrancyGuard for use with proxy contracts
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    error ReentrancyGuardReentrantCall();

    function __ReentrancyGuard_init() internal onlyInitializing {
        StorageSlot.getUint256Slot(REENTRANCY_GUARD_STORAGE).value = NOT_ENTERED;
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        StorageSlot.getUint256Slot(REENTRANCY_GUARD_STORAGE).value = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (StorageSlot.getUint256Slot(REENTRANCY_GUARD_STORAGE).value == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        StorageSlot.getUint256Slot(REENTRANCY_GUARD_STORAGE).value = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        StorageSlot.getUint256Slot(REENTRANCY_GUARD_STORAGE).value = NOT_ENTERED;
    }
}
