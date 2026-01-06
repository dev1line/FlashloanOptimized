# Contributing Guide

## Development Setup

### Prerequisites
- Foundry (nightly version recommended)
- Git
- Rust (for building Foundry from source if needed)

### Installation

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone repository
git clone <repo-url>
cd FlashloanOptimized

# Install dependencies
make install
# or
forge install
```

## Code Style

### Formatting
- Always run `forge fmt` before committing
- Code should follow Solidity style guide

### Testing Standards
- All new functions must have unit tests
- Fuzz tests required for all functions with parameters
- Invariant tests for core business logic
- Minimum 80% code coverage

## Test Commands

```bash
# Run all tests
make test

# Run fuzz tests (1000 runs)
make test-fuzz

# Run invariant tests
make test-invariant

# Generate gas report
make gas-report

# Full CI check
make ci
```

## Security Checklist

Before submitting PR:
- [ ] All tests pass
- [ ] Code formatted (`forge fmt`)
- [ ] Security tools run (Slither/Aderyn)
- [ ] Gas optimization reviewed
- [ ] No high/medium severity issues

## Commit Messages

Follow conventional commits:
- `feat: add new feature`
- `fix: fix bug`
- `test: add tests`
- `docs: update documentation`
- `refactor: refactor code`

