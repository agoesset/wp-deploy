#!/bin/bash
#===============================================================================
# Quick Install Script - Downloads and runs VPS Setup
#===============================================================================

set -e

REPO_URL="https://raw.githubusercontent.com/agoesset/wp-deploy/main/scripts"
INSTALL_DIR="${HOME}/vps-setup"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       VPS Setup Script - Quick Installer                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Create directories
echo "[1/4] Creating directories..."
mkdir -p "${INSTALL_DIR}/lib" "${INSTALL_DIR}/templates"
cd "${INSTALL_DIR}"

# Download main script
echo "[2/4] Downloading main script..."
curl -sSL "${REPO_URL}/vps-setup.sh" -o vps-setup.sh

# Download libraries
echo "[3/4] Downloading libraries..."
for lib in colors helpers vps-security webserver wordpress caching; do
    curl -sSL "${REPO_URL}/lib/${lib}.sh" -o "lib/${lib}.sh"
done

# Download templates
echo "[4/4] Downloading templates..."
for tpl in nginx.conf nginx-site.conf phpfpm-pool.conf wsc.conf; do
    curl -sSL "${REPO_URL}/templates/${tpl}" -o "templates/${tpl}"
done

# Make executable
chmod +x vps-setup.sh

echo ""
echo "✅ Installation complete!"
echo ""
echo "Location: ${INSTALL_DIR}"
echo ""
echo "To run the setup script:"
echo "  cd ${INSTALL_DIR}"
echo "  sudo ./vps-setup.sh"
echo ""

# Ask to run now
read -rp "Run the setup script now? [y/N]: " response
if [[ "$response" =~ ^[yY]$ ]]; then
    sudo ./vps-setup.sh
fi
