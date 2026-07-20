#!/bin/bash
set -e
echo "Running raw script part where i am installing docker"
echo "=================================================="
echo "   Full DevOps Stack Installation Script"
echo "=================================================="

# ─── REMOVE OLD DOCKER VERSIONS ──────────────────────
echo "[1/4] Removing old Docker versions..."
sudo apt remove -y $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null | cut -f1) 2>/dev/null || true

# ─── DOCKER INSTALLATION ─────────────────────────────
echo "[2/4] Installing Docker..."

sudo apt update -y
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker

docker --version
echo "Docker installed successfully!"

# ─── TREE INSTALLATION ───────────────────────────────
echo "Installing tree..."
sudo apt install -y tree
echo "Tree installed successfully!"

# ─── GROUP PERMISSIONS ───────────────────────────────
echo "Setting up group permissions..."

# Add current user to docker group
sudo usermod -aG docker ubuntu
echo "✅ Added ubuntu to docker group"

# ─── SUMMARY ─────────────────────────────────────────
echo ""
echo "=================================================="
echo "        Installation Complete! Summary:"
echo "=================================================="
echo "✅ Docker:         $(docker --version)"
echo "✅ Docker Compose: $(docker compose version)"
echo "✅ Java:           $(java -version 2>&1 | head -1)"
echo "✅ Tree:           $(tree --version | head -1)"

echo "Raw script finished at $(date)" >> /var/log/part2.log
