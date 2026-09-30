#!/bin/bash
# Autononext Build Setup Script
# Run this once to prepare the build environment

set -e

echo "=========================================="
echo "Autononext - Build Environment Setup"
echo "=========================================="

echo "[SETUP] Creating LLVM linker symlink..."
sudo ln -sf /usr/bin/ld /usr/lib/llvm-19/bin/ld.lld
echo "[SETUP] Linker symlink created"

echo "[SETUP] Verifying Flutter..."
/home/mxadm/fvm/versions/stable/bin/flutter --version

echo "[SETUP] Verifying dpkg-dev..."
dpkg-deb --version

echo "=========================================="
echo "Setup complete! Run 'make build-deb' to build a Debian package"
echo "=========================================="
