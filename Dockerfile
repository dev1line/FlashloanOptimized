# Multi-stage Dockerfile cho Flashloan Optimized Project
# Bao gồm Foundry, Slither, và Aderyn cho audit

FROM ubuntu:22.04

# Tránh interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies trong một layer để tối ưu cache
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

# Install Python tools
RUN pip3 install --no-cache-dir \
    solc-select \
    slither-analyzer

# Install Rust và Cargo (default profile để đảm bảo đầy đủ tools)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# Update Rust toolchain to latest stable
RUN rustup update stable && rustup default stable

# Install additional build dependencies needed for aderyn
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Aderyn - Try from crates.io first, if fails skip (it's optional)
# Aderyn có thể gặp lỗi compilation với một số phiên bản dependencies
# Nếu cần, có thể cài thủ công sau: cargo install --git https://github.com/Cyfrin/aderyn aderyn
RUN cargo install aderyn --locked 2>&1 || \
    echo "⚠️  Aderyn installation failed - skipping (optional tool, can install manually later)"

# Install Solidity compiler version 0.8.22 (theo foundry.toml)
RUN solc-select install 0.8.22 && solc-select use 0.8.22

# Clean up Rust build cache để giảm kích thước image
RUN rm -rf /root/.cargo/registry/cache /root/.cargo/git

# Set working directory
WORKDIR /workspace

# Default command - keep container running
CMD ["tail", "-f", "/dev/null"]

