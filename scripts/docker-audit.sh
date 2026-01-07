#!/bin/bash
# Script để chạy audit với Slither và Aderyn trong Docker

set -e

echo "=========================================="
echo "Docker Audit Script"
echo "=========================================="

# Kiểm tra Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker chưa được cài đặt. Vui lòng cài đặt Docker trước."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker daemon chưa chạy. Vui lòng khởi động Docker."
    exit 1
fi

# Build image nếu chưa có
echo "📦 Building Docker image..."
docker-compose build

# Start container
echo "🚀 Starting container..."
docker-compose up -d

# Đợi container sẵn sàng
echo "⏳ Waiting for container to be ready..."
sleep 5

# Install dependencies trong container (nếu chưa có)
echo "📥 Installing Forge dependencies..."
docker-compose exec -T flashloan-audit forge install || true

# Build contracts
echo "🔨 Building contracts..."
docker-compose exec -T flashloan-audit forge build --sizes

# Chạy Slither
echo ""
echo "=========================================="
echo "🔍 Running Slither Security Analysis"
echo "=========================================="
docker-compose exec -T flashloan-audit slither . \
    --filter-paths "lib,node_modules,cache,out" \
    --config-file slither.config.json \
    --print human-summary \
    --print json:slither-report.json || true

# Chạy Aderyn
echo ""
echo "=========================================="
echo "🔍 Running Aderyn Security Analysis"
echo "=========================================="
docker-compose exec -T flashloan-audit aderyn . --skip-build || true

echo ""
echo "=========================================="
echo "✅ Audit completed!"
echo "=========================================="
echo "Check slither-report.json for detailed Slither results"
echo "Aderyn results are displayed above"

