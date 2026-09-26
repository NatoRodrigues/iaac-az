#!/usr/bin/env bash
echo "[INFO] Waiting for cloud-init..."

if command -v cloud-init >/dev/null 2>&1; then
    cloud-init status --wait || true
fi

echo "[INFO] Waiting for apt locks..."

while \
  fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
  fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
  fuser /var/cache/apt/archives/lock >/dev/null 2>&1
do
    sleep 5
done

echo "[INFO] Refreshing repositories..."

rm -rf /var/lib/apt/lists/*

apt-get clean

apt-get \
  -o Acquire::Retries=5 \
  -o Acquire::ForceIPv4=true \
  update
set -euo pipefail

echo "[INFO] Starting production VM configuration..."

export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Waiting for cloud-init..."
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init status --wait || true
fi

echo "[INFO] Waiting for APT locks..."
while \
  fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
  fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
  fuser /var/cache/apt/archives/lock >/dev/null 2>&1
do
  sleep 5
done

echo "[INFO] Rebuilding package indexes..."
rm -rf /var/lib/apt/lists/*
mkdir -p /var/lib/apt/lists/partial

apt-get clean

apt-get \
  -o Acquire::Retries=5 \
  -o Acquire::ForceIPv4=true \
  update

echo "[INFO] Verifying package indexes..."
apt-cache policy nginx
apt-cache policy docker.io

echo "[INFO] Installing production packages..."
apt-get \
  -o Acquire::Retries=5 \
  -o Acquire::ForceIPv4=true \
  install -y \
    nginx \
    docker.io \
    curl \
    ca-certificates \
    unzip
