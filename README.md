# Flashloan Optimized - Smart Contract Repository

Repository chứa các smart contract về kỹ thuật flashloan, cho phép user custom workflow khi vay từ AAVE hoặc sử dụng flash swap của Uniswap V3.

## Tính năng

- ✅ **AAVE Flashloan**: Vay flashloan trực tiếp từ AAVE Pool
- ✅ **Uniswap Flash Swap**: Sử dụng flash swap của Uniswap V3
- ✅ **Custom Workflow**: Cho phép user định nghĩa workflow giao dịch tùy chỉnh
- ✅ **Upgradeable Contracts**: Sử dụng UUPS proxy pattern để có thể upgrade
- ✅ **Security**: Reentrancy guards, access control, input validation
- ✅ **Fee Management**: Hệ thống phí linh hoạt với profit validation

## Cấu trúc Project

```
FlashloanOptimized/
├── src/
│   ├── interfaces/          # Các interface cho AAVE, Uniswap, ERC20
│   ├── utils/               # Ownable, Pausable, ReentrancyGuard upgradeable
│   ├── examples/            # Ví dụ workflow implementation
│   ├── FlashloanBase.sol    # Base contract với các tính năng chung
│   ├── AAVEFlashloan.sol    # Contract cho AAVE flashloan
│   └── UniswapFlashSwap.sol # Contract cho Uniswap flash swap
├── test/                    # Test cases
├── script/                  # Deployment scripts
└── lib/                     # Dependencies (OpenZeppelin, forge-std)
```

## Contracts

### 1. FlashloanBase

Base contract cung cấp các tính năng chung:
- Upgradeability (UUPS pattern)
- Access control (Ownable)
- Reentrancy protection
- Pausable functionality
- Fee management
- Workflow execution

### 2. AAVEFlashloan

Contract để thực hiện flashloan từ AAVE:
- Gọi `executeFlashloan()` với token, amount, workflow và data
- AAVE sẽ gọi callback `executeOperation()`
- Workflow được thực thi trong callback
- Tự động hoàn trả và tính toán profit/fee

### 3. UniswapFlashSwap

Contract để thực hiện flash swap từ Uniswap V3:
- Gọi `executeFlashSwap()` với pool, tokens, amount, workflow và data
- Uniswap sẽ gọi callback `uniswapV3SwapCallback()`
- Workflow được thực thi trong callback
- Tự động hoàn trả và tính toán profit/fee

## Workflow Interface

Để tạo custom workflow, implement interface `IFlashloanWorkflow`:

```solidity
interface IFlashloanWorkflow {
    function executeWorkflow(
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, uint256 profit);
}
```

### Ví dụ Workflow

Xem `src/examples/SimpleSwapWorkflow.sol` để biết cách implement một workflow đơn giản.

## Installation

```bash
# Clone repository
git clone <repo-url>
cd FlashloanOptimized

# Install dependencies (đã được cài qua forge install)
forge install
```

## Deployment

### 1. Setup Environment

Tạo file `.env`:
```
PRIVATE_KEY=your_private_key
RPC_URL=your_rpc_url
```

### 2. Deploy Contracts

```bash
# Deploy AAVE Flashloan
forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL --broadcast

# Hoặc deploy riêng từng contract
forge create src/AAVEFlashloan.sol:AAVEFlashloan --constructor-args <args>
```

### 3. Initialize Contracts

Sau khi deploy, cần initialize:
- Owner address
- AAVE Pool address (cho AAVEFlashloan)
- Fee settings
- Min profit settings

## Usage

### AAVE Flashloan

```solidity
// 1. Deploy và initialize contract
AAVEFlashloan flashloan = AAVEFlashloan(proxyAddress);

// 2. Deploy workflow contract
SimpleSwapWorkflow workflow = new SimpleSwapWorkflow(routerAddress);

// 3. Execute flashloan
flashloan.executeFlashloan(
    tokenAddress,      // Token muốn vay
    amount,            // Số lượng
    address(workflow), // Workflow contract
    workflowData       // Data cho workflow
);
```

### Uniswap Flash Swap

```solidity
// 1. Deploy và initialize contract
UniswapFlashSwap flashSwap = UniswapFlashSwap(proxyAddress);

// 2. Execute flash swap
flashSwap.executeFlashSwap(
    poolAddress,       // Uniswap V3 pool
    tokenIn,           // Token nhận
    tokenOut,          // Token trả
    amountIn,          // Số lượng nhận
    address(workflow), // Workflow contract
    workflowData       // Data cho workflow
);
```

## Security Features

1. **Reentrancy Protection**: Sử dụng ReentrancyGuard
2. **Access Control**: Chỉ owner mới có thể thay đổi settings
3. **Input Validation**: Validate tất cả inputs
4. **Pausable**: Có thể pause contract trong trường hợp khẩn cấp
5. **Profit Validation**: Đảm bảo profit đủ để cover fees
6. **Upgrade Safety**: UUPS pattern với authorization

## Fee Structure

- **Fee BPS**: Fee tính bằng basis points (1 BPS = 0.01%)
- **Max Fee**: Tối đa 10% (1000 BPS)
- **Min Profit**: Profit tối thiểu cần đạt được
- **Fee Collection**: Fees được lưu trong contract, owner có thể withdraw

## Testing

```bash
# Run all tests
forge test

# Run với verbose output
forge test -vvv

# Run specific test
forge test --match-test testAAVEFlashloan
```

## Upgrade Process

Contracts sử dụng UUPS proxy pattern:

1. Deploy implementation mới
2. Owner gọi `upgradeToAndCall()` trên proxy
3. Implementation mới phải implement UUPSUpgradeable

```solidity
// Upgrade implementation
flashloan.upgradeToAndCall(newImplementation, upgradeData);
```

## Input/Output

### Input
- `token`: Địa chỉ token muốn vay
- `amount`: Số lượng token muốn vay
- `workflow`: Địa chỉ contract workflow
- `workflowData`: Data tùy chỉnh cho workflow

### Output
- **Success**: Workflow thực thi thành công, profit được transfer cho user (sau khi trừ fee)
- **Failure**: Transaction revert, user chỉ mất gas fee

## Lưu ý

1. **Gas Costs**: Flashloan operations tốn gas đáng kể
2. **Profitability**: Đảm bảo workflow tạo đủ profit để cover fees và gas
3. **Slippage**: Cần xử lý slippage trong workflow
4. **Testing**: Test kỹ trên testnet trước khi deploy mainnet
5. **Audit**: Nên audit contracts trước khi deploy production

## License

MIT

## Contributing

Contributions are welcome! Please open an issue or PR.

## Disclaimer

Smart contracts có rủi ro. Sử dụng trên mainnet với trách nhiệm của bạn. Tác giả không chịu trách nhiệm cho bất kỳ tổn thất nào.
