.PHONY: install build test test-fuzz test-invariant fmt lint coverage clean slither aderyn gas-report deploy security pre-push ci \
	docker-build docker-up docker-down docker-shell docker-slither docker-aderyn docker-security docker-test docker-build-contracts docker-clean \
	install-hooks

# Install dependencies
install:
	forge install

# Install git hooks for automatic formatting
install-hooks:
	@echo "Installing git hooks..."
	@bash scripts/install-git-hooks.sh

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
	@echo "Running Slither security analysis..."
	slither . \
		--filter-paths "lib,node_modules,cache,out" \
		--config-file slither.config.json \
		--print human-summary \
		--print json:slither-report.json || true

# Run Aderyn
aderyn:
	@echo "Running Aderyn security analysis..."
	aderyn . --skip-build || true
	@if [ -f report.md ]; then \
		echo "✅ Aderyn analysis completed. Generating HTML report and console summary..."; \
		python3 scripts/aderyn-to-html.py || true; \
	fi

# Generate gas report
gas-report:
	forge test --gas-report

# Run security checks
security: slither aderyn
	@echo "Security checks completed!"

# Pre-push check (run before pushing code)
pre-push: lint build test security
	@echo "✅ Pre-push checks passed!"

# Full CI check
ci: lint build test test-invariant security gas-report

# ============================================
# Docker Commands
# ============================================

# Build Docker image
docker-build:
	@echo "Building Docker image..."
	docker-compose build

# Start Docker container
docker-up:
	@echo "Starting Docker container..."
	docker-compose up -d

# Stop Docker container
docker-down:
	@echo "Stopping Docker container..."
	docker-compose down

# Get shell in Docker container
docker-shell:
	@echo "Opening shell in Docker container..."
	docker-compose exec flashloan-audit /bin/bash

# Build contracts in Docker
docker-build-contracts:
	@echo "Building contracts in Docker..."
	docker-compose exec flashloan-audit forge build --sizes

# Run Slither in Docker
docker-slither:
	@echo "Running Slither security analysis in Docker..."
	docker-compose exec flashloan-audit slither . \
		--filter-paths "lib,node_modules,cache,out" \
		--config-file slither.config.json \
		--print human-summary \
		--json slither-report.json || true

# Run Aderyn in Docker
docker-aderyn:
	@echo "Running Aderyn security analysis in Docker..."
	@docker-compose exec flashloan-audit bash -c "aderyn . --skip-build 2>&1" | grep -vE "(panicked at|note: run with|backtrace)" || true
	@if docker-compose exec -T flashloan-audit test -f report.md 2>/dev/null; then \
		echo "✅ Aderyn analysis completed. Generating HTML report and console summary..."; \
		docker-compose exec -T flashloan-audit python3 scripts/aderyn-to-html.py || \
		(docker-compose exec flashloan-audit python3 scripts/aderyn-to-html.py); \
	else \
		echo "⚠️  Aderyn report not found. Check for errors above."; \
	fi

# Run security checks in Docker
docker-security: docker-slither docker-aderyn
	@echo "Security checks completed in Docker!"

# Run tests in Docker
docker-test:
	@echo "Running tests in Docker..."
	docker-compose exec flashloan-audit forge test -vv

# Run fuzz tests in Docker
docker-test-fuzz:
	@echo "Running fuzz tests in Docker..."
	docker-compose exec flashloan-audit forge test --fuzz-runs 1000 -vv

# Run invariant tests in Docker
docker-test-invariant:
	@echo "Running invariant tests in Docker..."
	docker-compose exec flashloan-audit forge test --match-path "**/invariant/**/*.t.sol" --fuzz-runs 256 -vv

# Clean Docker containers and volumes
docker-clean:
	@echo "Cleaning Docker containers and volumes..."
	docker-compose down -v
	docker rmi flashloan-audit:latest || true

# Run audit automation (parse reports and generate HTML report)
audit-autofix:
	@echo "Running audit automation and generating HTML report..."
	python3 scripts/audit-autofix.py --report-only

# Run audit automation in Docker
docker-audit-autofix:
	@echo "Running audit automation with auto-fix in Docker..."
	docker-compose exec flashloan-audit python3 scripts/audit-autofix.py

# Run full audit workflow (run audits + parse + fix + report)
audit-full: docker-security audit-autofix
	@echo "✅ Full audit workflow completed! Check audit-summary.md for results."

# Run full audit workflow in Docker
docker-audit-full: docker-security docker-audit-autofix
	@echo "✅ Full audit workflow completed in Docker! Check audit-summary.md for results."

# Full CI in Docker
docker-ci: docker-build-contracts docker-test docker-test-invariant docker-security
	@echo "✅ Docker CI checks completed!"

