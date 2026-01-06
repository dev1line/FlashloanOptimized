// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AAVEFlashloan} from "../src/AAVEFlashloan.sol";
import {UniswapFlashSwap} from "../src/UniswapFlashSwap.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract FlashloanTest is Test {
    AAVEFlashloan public aaveFlashloan;
    UniswapFlashSwap public uniswapFlashSwap;
    
    address public owner = address(1);
    address public user = address(2);
    
    function setUp() public {
        // Deploy AAVE Flashloan
        AAVEFlashloan impl = new AAVEFlashloan();
        bytes memory initData = abi.encodeWithSelector(
            AAVEFlashloan.initialize.selector,
            owner,
            address(0x123), // mock pool
            50, // 0.5% fee
            10 // 0.1% min profit
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        aaveFlashloan = AAVEFlashloan(address(proxy));
        
        // Deploy Uniswap Flash Swap
        UniswapFlashSwap uniswapImpl = new UniswapFlashSwap();
        bytes memory uniswapInitData = abi.encodeWithSelector(
            UniswapFlashSwap.initialize.selector,
            owner,
            50,
            10
        );
        ERC1967Proxy uniswapProxy = new ERC1967Proxy(address(uniswapImpl), uniswapInitData);
        uniswapFlashSwap = UniswapFlashSwap(address(uniswapProxy));
    }
    
    function testAAVEFlashloanInitialization() public view {
        assertEq(aaveFlashloan.owner(), owner);
        assertEq(aaveFlashloan.feeBps(), 50);
        assertEq(aaveFlashloan.minProfitBps(), 10);
    }
    
    function testUniswapFlashSwapInitialization() public view {
        assertEq(uniswapFlashSwap.owner(), owner);
        assertEq(uniswapFlashSwap.feeBps(), 50);
        assertEq(uniswapFlashSwap.minProfitBps(), 10);
    }
    
    function testSetFee() public {
        vm.prank(owner);
        aaveFlashloan.setFee(100);
        assertEq(aaveFlashloan.feeBps(), 100);
    }
    
    function testSetFeeRevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        aaveFlashloan.setFee(100);
    }
    
    function testPause() public {
        vm.prank(owner);
        aaveFlashloan.pause();
        assertTrue(aaveFlashloan.paused());
    }
    
    // ============ FUZZ TESTS ============
    
    /// @notice Fuzz test for setFee with various values
    function testFuzz_SetFee(uint256 fee) public {
        // Bound fee to valid range: 0 to MAX_FEE_BPS (1000)
        fee = bound(fee, 0, 1000);
        
        vm.prank(owner);
        aaveFlashloan.setFee(fee);
        assertEq(aaveFlashloan.feeBps(), fee);
    }
    
    /// @notice Fuzz test for setFee reverts when too high
    function testFuzz_SetFee_RevertsIfTooHigh(uint256 fee) public {
        // Bound fee to invalid range: > MAX_FEE_BPS (1000)
        fee = bound(fee, 1001, type(uint256).max);
        
        vm.prank(owner);
        vm.expectRevert();
        aaveFlashloan.setFee(fee);
    }
    
    /// @notice Fuzz test for setFee reverts if not owner
    function testFuzz_SetFee_RevertsIfNotOwner(address notOwner, uint256 fee) public {
        // Ensure notOwner is not the owner
        vm.assume(notOwner != owner);
        fee = bound(fee, 0, 1000);
        
        vm.prank(notOwner);
        vm.expectRevert();
        aaveFlashloan.setFee(fee);
    }
    
    /// @notice Fuzz test for initialization values
    function testFuzz_Initialization(
        address _owner,
        uint256 _feeBps,
        uint256 _minProfitBps
    ) public {
        // Bound values to valid ranges
        vm.assume(_owner != address(0));
        _feeBps = bound(_feeBps, 0, 1000);
        _minProfitBps = bound(_minProfitBps, 0, 1000);
        
        // Deploy new AAVE Flashloan with fuzzed values
        AAVEFlashloan impl = new AAVEFlashloan();
        bytes memory initData = abi.encodeWithSelector(
            AAVEFlashloan.initialize.selector,
            _owner,
            address(0x123), // mock pool
            _feeBps,
            _minProfitBps
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        AAVEFlashloan testFlashloan = AAVEFlashloan(address(proxy));
        
        // Verify initialization
        assertEq(testFlashloan.owner(), _owner);
        assertEq(testFlashloan.feeBps(), _feeBps);
        assertEq(testFlashloan.minProfitBps(), _minProfitBps);
    }
    
    /// @notice Fuzz test for Uniswap initialization values
    function testFuzz_UniswapInitialization(
        address _owner,
        uint256 _feeBps,
        uint256 _minProfitBps
    ) public {
        // Bound values to valid ranges
        vm.assume(_owner != address(0));
        _feeBps = bound(_feeBps, 0, 1000);
        _minProfitBps = bound(_minProfitBps, 0, 1000);
        
        // Deploy new Uniswap Flash Swap with fuzzed values
        UniswapFlashSwap uniswapImpl = new UniswapFlashSwap();
        bytes memory uniswapInitData = abi.encodeWithSelector(
            UniswapFlashSwap.initialize.selector,
            _owner,
            _feeBps,
            _minProfitBps
        );
        ERC1967Proxy uniswapProxy = new ERC1967Proxy(address(uniswapImpl), uniswapInitData);
        UniswapFlashSwap testFlashSwap = UniswapFlashSwap(address(uniswapProxy));
        
        // Verify initialization
        assertEq(testFlashSwap.owner(), _owner);
        assertEq(testFlashSwap.feeBps(), _feeBps);
        assertEq(testFlashSwap.minProfitBps(), _minProfitBps);
    }
}

