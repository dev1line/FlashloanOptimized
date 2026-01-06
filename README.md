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

Dự án sử dụng Foundry với các best practices:

### Test Types

1. **Unit Tests**: Test các function riêng lẻ
2. **Fuzz Tests**: Test với hàng nghìn giá trị input ngẫu nhiên
3. **Invariant Tests**: Test các invariants của hệ thống qua chuỗi operations ngẫu nhiên
4. **Integration Tests**: Test tích hợp giữa các contracts

### Test Commands

```bash
# Run all tests
make test
# or
forge test

# Run với verbose output
forge test -vvv

# Run fuzz tests (1000 runs)
make test-fuzz
# or
forge test --fuzz-runs 1000

# Run invariant tests
make test-invariant
# or
forge test --match-path "**/invariant/**/*.t.sol" --fuzz-runs 256

# Generate gas report
make gas-report
# or
forge test --gas-report

# Comprehensive test suite
./scripts/test.sh

# Full CI check (lint, build, test, security)
make ci
```

### Test Coverage

- ✅ 85+ tests covering all functionality
- ✅ Fuzz tests với 1000 runs cho mỗi function có parameters
- ✅ Invariant tests với Handler pattern
- ✅ Gas optimization reporting

### Invariant Testing

Dự án sử dụng Invariant Testing với Handler pattern để test các invariants quan trọng:

- **Fee Limit**: Fee BPS luôn <= MAX_FEE_BPS
- **Solvency**: Contract không bao giờ mất tokens
- **Owner Consistency**: Owner luôn được set và không đổi
- **Pool Validity**: Pool address luôn valid

Xem `test/invariant/FlashloanInvariant.t.sol` để biết chi tiết.

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

## CI/CD

Dự án sử dụng GitHub Actions để tự động:

- ✅ **Lint**: Format check với `forge fmt --check`
- ✅ **Build**: Compile contracts và check sizes
- ✅ **Test**: Chạy unit, fuzz, và invariant tests
- ✅ **Security**: Chạy Slither và Aderyn (nếu available)
- ✅ **Coverage**: Generate coverage reports

Pipeline tự động chạy trên mỗi push và PR.

## Performance

### Compilation

- Optimizer runs: 20000
- Via-IR: Enabled
- Parallel compilation: Enabled

### Testing

- Fuzz runs: 1000 (default), 100 (CI)
- Invariant runs: 256 (default), 20 (CI)
- Seed: Fixed for reproducibility

### Contract Sizes

- AAVEFlashloan: ~2159 bytes (within limit)
- UniswapFlashSwap: Similar size
- All contracts under EIP-170 limit (24576 bytes)

## Resources

### Foundry Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [Forge Reference](https://book.getfoundry.sh/reference/forge/)

### Best Practices

- [Foundry Best Practices](https://github.com/foundry-rs/foundry/tree/master/testdata)
- [Solmate](https://github.com/transmissions11/solmate) - Gas-optimized library
- [Invariant Testing Examples](https://github.com/lucas-manuel/invariant-examples)

## License

MIT

## Development & Best Practices

### Code Quality

Dự án tuân theo Foundry best practices:

- ✅ **Solidity-native testing**: Tất cả tests viết bằng Solidity
- ✅ **Fuzzing**: Fuzz tests với 1000+ runs
- ✅ **Invariant Testing**: System-wide invariant checks
- ✅ **Gas Optimization**: Optimizer runs 20000, via-IR enabled
- ✅ **CI/CD**: GitHub Actions tự động test và lint

### Project Structure

```
FlashloanOptimized/
├── src/
│   ├── interfaces/          # Interfaces
│   ├── utils/               # Utility contracts
│   ├── examples/            # Example workflows
│   ├── FlashloanBase.sol
│   ├── AAVEFlashloan.sol
│   └── UniswapFlashSwap.sol
├── test/
│   ├── mocks/               # Mock contracts
│   ├── invariant/           # Invariant tests
│   ├── *.t.sol              # Unit & fuzz tests
│   └── IntegrationTest.t.sol
├── script/                  # Deployment scripts
├── lib/                     # Dependencies
├── .github/workflows/       # CI/CD pipelines
├── foundry.toml            # Foundry configuration
├── slither.config.json     # Slither config
├── .aderynconfig.toml      # Aderyn config
└── Makefile                # Development commands
```

### Configuration Files

- `foundry.toml`: Cấu hình Foundry với optimizer, fuzz, invariant settings
- `slither.config.json`: Cấu hình Slither static analysis
- `.aderynconfig.toml`: Cấu hình Aderyn security scanner
- `.github/workflows/ci.yml`: CI/CD pipeline

### Security Tools

```bash
# Run Slither
make slither
# or
slither .

# Run Aderyn
make aderyn
# or
aderyn .

# Run all security checks
make security
```

### Gas Optimization

- Contracts được compile với `optimizer_runs = 20000` và `via_ir = true`
- Gas report tự động generate khi chạy tests
- Contract size limit: 24576 bytes (EIP-170)

## Contributing

Xem [CONTRIBUTING.md](./CONTRIBUTING.md) để biết hướng dẫn chi tiết.

Contributions are welcome! Please:

1. Fork repository
2. Create feature branch
3. Run tests (`make ci`)
4. Submit PR

### Development Workflow

```bash
# 1. Install dependencies
make install

# 2. Make changes
# ... edit code ...

# 3. Format code
make fmt

# 4. Run tests
make test

# 5. Run full CI check
make ci

# 6. Commit and push
git commit -m "feat: your changes"
git push
```

## Disclaimer

Smart contracts có rủi ro. Sử dụng trên mainnet với trách nhiệm của bạn. Tác giả không chịu trách nhiệm cho bất kỳ tổn thất nào.
