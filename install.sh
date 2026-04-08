#!/bin/bash
set -euo pipefail

# pwrstat-node-exporter installer
# Installs the exporter as a systemd service with one command

INSTALL_DIR="/opt/pwrstat-node-exporter"
SERVICE_NAME="pwrstat-exporter"
SERVICE_FILE="pwrstat-exporter.service"
EXPORTER_SCRIPT="pwrstat_exporter.py"
SUDOERS_FILE="/etc/sudoers.d/pwrstat"
EXPORTER_PORT=9182

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Must run as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   log_error "Usage: sudo $0"
   exit 1
fi

# Check if pwrstat is installed
check_pwrstat() {
    if ! command -v pwrstat &> /dev/null; then
        log_error "pwrstat command not found!"
        echo ""
        echo "Please install CyberPower PowerPanel for Linux first:"
        echo "  1. Download from: https://www.cyberpowersystems.com/products/software/powerpanel-linux/"
        echo "  2. Install: sudo dpkg -pwrstat ppa22010.upg  (or rpm -i for RHEL)"
        echo "  3. Verify: pwrstat -status"
        echo ""
        echo "After installing PowerPanel, run this installer again."
        exit 1
    fi
    log_info "✓ pwrstat found: $(which pwrstat)"
}

# Check if Python 3 is available
check_python() {
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not installed"
        log_info "Install with: sudo apt install python3  OR  sudo dnf install python3"
        exit 1
    fi
    log_info "✓ Python 3 found: $(python3 --version)"
}

# Stop existing service if running
stop_existing() {
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "Stopping existing $SERVICE_NAME service..."
        systemctl stop $SERVICE_NAME
    fi
}

# Create installation directory
setup_directory() {
    log_info "Creating installation directory: $INSTALL_DIR"
    mkdir -p $INSTALL_DIR
}

# Install exporter script
install_exporter() {
    log_info "Installing exporter script..."
    cp "$EXPORTER_SCRIPT" "$INSTALL_DIR/$EXPORTER_SCRIPT"
    chmod +x "$INSTALL_DIR/$EXPORTER_SCRIPT"
    log_info "✓ Exporter installed to $INSTALL_DIR/$EXPORTER_SCRIPT"
}

# Install systemd service
install_service() {
    log_info "Installing systemd service..."
    cp "$SERVICE_FILE" /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    log_info "✓ Systemd service installed"
}

# Configure sudo for pwrstat
configure_sudo() {
    log_info "Configuring passwordless sudo for pwrstat..."
    cat > $SUDOERS_FILE << 'EOF'
# Allow pwrstat command without password for pwrstat-exporter service
ALL ALL=(ALL) NOPASSWD: /usr/bin/pwrstat
EOF
    chmod 440 $SUDOERS_FILE
    log_info "✓ Sudoers configured"
}

# Enable and start service
start_service() {
    log_info "Enabling and starting $SERVICE_NAME service..."
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME

    # Wait a moment for service to start
    sleep 2

    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "✓ $SERVICE_NAME service is running"
    else
        log_error "$SERVICE_NAME service failed to start"
        log_info "Check logs with: journalctl -u $SERVICE_NAME -f"
        exit 1
    fi
}

# Verify the exporter is working
verify() {
    log_info "Verifying exporter metrics..."
    sleep 2

    if curl -sf http://localhost:$EXPORTER_PORT/metrics > /dev/null; then
        log_info "✓ Exporter is serving metrics on http://localhost:$EXPORTER_PORT/metrics"
        echo ""
        echo "Sample metrics:"
        curl -s http://localhost:$EXPORTER_PORT/metrics | head -20
    else
        log_error "Exporter is not responding on port $EXPORTER_PORT"
        log_info "Check logs: journalctl -u $SERVICE_NAME -f"
        exit 1
    fi
}

# Print next steps
print_next_steps() {
    echo ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "  pwrstat-node-exporter installed successfully! 🎉"
    log_info "═══════════════════════════════════════════════════════"
    echo ""
    echo "Service Management:"
    echo "  Status:   systemctl status $SERVICE_NAME"
    echo "  Stop:     systemctl stop $SERVICE_NAME"
    echo "  Start:    systemctl start $SERVICE_NAME"
    echo "  Logs:     journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "Metrics Endpoint:"
    echo "  http://localhost:$EXPORTER_PORT/metrics"
    echo "  http://localhost:$EXPORTER_PORT/health"
    echo ""
    echo "Next Step: Configure Prometheus Scrape"
    echo "  Add to your kube-prometheus-stack values:"
    echo ""
    echo "  prometheus:"
    echo "    prometheusSpec:"
    echo "      additionalScrapeConfigs:"
    echo "        - job_name: 'pwrstat-exporter'"
    echo "          scrape_interval: 30s"
    echo "          static_configs:"
    echo "            - targets: ['<YOUR_NODE_IP>:$EXPORTER_PORT']"
    echo ""
    log_info "═══════════════════════════════════════════════════════"
}

# Main installation flow
main() {
    echo ""
    log_info "Starting pwrstat-node-exporter installation..."
    echo ""

    check_pwrstat
    check_python
    stop_existing
    setup_directory
    install_exporter
    install_service
    configure_sudo
    start_service
    verify
    print_next_steps
}

main "$@"
