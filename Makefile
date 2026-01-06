.PHONY: install build test test-fuzz test-invariant fmt lint coverage clean slither aderyn gas-report deploy

# Install dependencies
install:
	forge install

# Build contracts
build:
	forge build --sizes

# Run all tests
test:
	forge test -vv

# Run fuzz tests with high runs
test-fuzz:
	forge test --fuzz-runs 1000 -vv

# Run invariant tests
test-invariant:
	forge test --match-path "**/invariant/**/*.t.sol" --fuzz-runs 256 -vv

# Format code
fmt:
	forge fmt

# Lint check
lint:
	forge fmt --check

# Generate coverage report
coverage:
	forge coverage --report lcov

# Clean build artifacts
clean:
	forge clean
	rm -rf cache out

# Run Slither
slither:
	slither . --filter-paths "lib,node_modules"

# Run Aderyn
aderyn:
	aderyn .

# Generate gas report
gas-report:
	forge test --gas-report

# Run security checks
security: slither aderyn

# Full CI check
ci: lint build test test-invariant security gas-report

