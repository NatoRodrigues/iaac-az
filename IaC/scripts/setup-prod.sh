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
#!/usr/bin/env bash

set -euo pipefail

echo "[INFO] Starting production VM configuration..."

export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Updating package repository..."
apt-get update

echo "[INFO] Installing production packages..."
apt-get install -y \
  nginx \
  docker.io \
  curl \
  jq \
  ca-certificates \
  unzip

echo "[INFO] Enabling Docker..."
systemctl enable docker
systemctl start docker

echo "[INFO] Enabling Nginx..."
systemctl enable nginx
systemctl start nginx

echo "[INFO] Adding azureuser to the Docker group..."
usermod -aG docker azureuser

echo "[INFO] Creating application directories..."
mkdir -p /opt/ops-toolkit/app
mkdir -p /opt/ops-toolkit/logs
mkdir -p /opt/ops-toolkit/config

chown -R azureuser:azureuser /opt/ops-toolkit

echo "[INFO] Creating production landing page..."
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Ops Toolkit</title>
</head>
<body>
  <h1>Ops Toolkit Production Server</h1>
  <p>Nginx is running successfully.</p>
</body>
</html>
EOF

echo "[INFO] Validating Nginx configuration..."
nginx -t

echo "[INFO] Reloading Nginx..."
systemctl reload nginx

echo "[INFO] Validating installed services..."

if systemctl is-active --quiet nginx; then
  echo "[OK] Nginx is running."
else
  echo "[ERROR] Nginx failed to start."
  exit 1
fi

if systemctl is-active --quiet docker; then
  echo "[OK] Docker is running."
else
  echo "[ERROR] Docker failed to start."
  exit 1
fi

echo "[INFO] Installed versions:"
nginx -v
docker --version
curl --version | head -n 1
jq --version

echo "[SUCCESS] Production VM configuration completed."
