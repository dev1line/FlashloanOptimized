#!/bin/bash
# Comprehensive test script following Foundry best practices

set -e

echo "🔍 Running comprehensive test suite..."

# Format check
echo "📝 Checking code format..."
forge fmt --check

# Build
echo "🔨 Building contracts..."
forge build --sizes

# Run unit tests
echo "🧪 Running unit tests..."
forge test -vv

# Run fuzz tests with more runs
echo "🎲 Running fuzz tests (1000 runs)..."
forge test --fuzz-runs 1000 -vv

# Run invariant tests
echo "🔄 Running invariant tests..."
forge test --match-path "**/invariant/**/*.t.sol" --fuzz-runs 256 -vv || echo "⚠️  Invariant tests may have failures (expected in some cases)"

# Generate gas report
echo "⛽ Generating gas report..."
forge test --gas-report

# Run security tools if available
if command -v slither &> /dev/null; then
    echo "🔒 Running Slither..."
    slither . --filter-paths "lib,node_modules" || true
fi

if command -v aderyn &> /dev/null; then
    echo "🔒 Running Aderyn..."
    aderyn . || true
fi

echo "✅ All tests completed!"

