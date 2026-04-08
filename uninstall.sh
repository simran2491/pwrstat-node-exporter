#!/bin/bash
set -euo pipefail

# pwrstat-node-exporter uninstaller

INSTALL_DIR="/opt/pwrstat-node-exporter"
SERVICE_NAME="pwrstat-exporter"
SUDOERS_FILE="/etc/sudoers.d/pwrstat"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} This script must be run as root"
   exit 1
fi

log_info "Stopping $SERVICE_NAME service..."
systemctl stop $SERVICE_NAME 2>/dev/null || true
systemctl disable $SERVICE_NAME 2>/dev/null || true

log_info "Removing systemd service..."
rm -f /etc/systemd/system/$SERVICE_NAME.service
systemctl daemon-reload

log_info "Removing installation directory..."
rm -rf $INSTALL_DIR

log_info "Removing sudoers configuration..."
rm -f $SUDOERS_FILE

log_info "✓ pwrstat-node-exporter uninstalled successfully"
