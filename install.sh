#!/bin/bash
set -euo pipefail

##############################################################################
# pwrstat-node-exporter - Self-contained installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/simran2491/pwrstat-node-exporter/main/install.sh | sudo bash
#
# Or with specific version:
#   curl -fsSL https://raw.githubusercontent.com/simran2491/pwrstat-node-exporter/v1.0.0/install.sh | sudo bash
##############################################################################

REPO_OWNER="simran2491"
REPO_NAME="pwrstat-node-exporter"
REPO_BRANCH="main"
INSTALL_DIR="/opt/pwrstat-node-exporter"
SERVICE_NAME="pwrstat-exporter"
SUDOERS_FILE="/etc/sudoers.d/pwrstat"
EXPORTER_PORT=9182

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${BLUE}▸${NC} $1"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   log_info "Usage: curl -fsSL ... | sudo bash"
   exit 1
fi

# Check if pwrstat is installed - MUST BE FIRST
check_pwrstat() {
    if ! command -v pwrstat &> /dev/null; then
        echo ""
        log_error "pwrstat command not found!"
        echo ""
        echo "════════════════════════════════════════════════════════"
        echo ""
        echo "⚠️  This exporter requires CyberPower PowerPanel for Linux"
        echo "   which provides the 'pwrstat' command."
        echo ""
        echo "📥 Install PowerPanel BEFORE running this installer:"
        echo ""
        echo "   1. Download the correct version for your system:"
        echo "      https://www.cyberpowersystems.com/products/software/powerpanel-linux/"
        echo ""
        echo "   2. Install the package:"
        echo "      # For Debian/Ubuntu:"
        echo "      sudo dpkg -i pwrstat*.deb"
        echo ""
        echo "      # For RHEL/CentOS/Fedora:"
        echo "      sudo rpm -i pwrstat*.rpm"
        echo ""
        echo "   3. Verify installation:"
        echo "      pwrstat -status"
        echo ""
        echo "   4. Then run this installer again:"
        echo "      curl -fsSL https://raw.githubusercontent.com/simranjeet/91/pwrstat-node-exporter/main/install.sh | sudo bash"
        echo ""
        echo "════════════════════════════════════════════════════════"
        echo ""
        exit 1
    fi
    log_info "✓ pwrstat found at $(which pwrstat)"
}

# Parse optional arguments
PWRSTAT_PATH="/usr/bin/pwrstat"

while [[ $# -gt 0 ]]; do
    case $1 in
        --pwrstat-path)
            PWRSTAT_PATH="$2"
            shift 2
            ;;
        --version)
            REPO_BRANCH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --pwrstat-path PATH    Path to pwrstat binary (default: /usr/bin/pwrstat)"
            echo "  --version VERSION      Install specific version/tag (default: main)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if pwrstat is installed
check_pwrstat() {
    if ! command -v pwrstat &> /dev/null; then
        log_error "pwrstat command not found!"
        echo ""
        echo "Please install CyberPower PowerPanel for Linux first:"
        echo "  1. Download: https://www.cyberpowersystems.com/products/software/powerpanel-linux/"
        echo "  2. Install: sudo dpkg -i pwrstat*.deb  (or sudo rpm -i for RHEL)"
        echo "  3. Verify: pwrstat -status"
        echo ""
        echo "After installing PowerPanel, run this installer again."
        exit 1
    fi
    log_info "✓ pwrstat found at $(which pwrstat)"
}

# Check Python 3
check_python() {
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not installed"
        log_info "Install with: sudo apt install python3  OR  sudo dnf install python3"
        exit 1
    fi
    log_info "✓ Python 3 found: $(python3 --version)"
}

# Get base URL for downloading files
get_base_url() {
    if [[ "$REPO_BRANCH" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        # It's a version tag
        echo "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/refs/tags/${REPO_BRANCH}"
    else
        # It's a branch
        echo "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/refs/heads/${REPO_BRANCH}"
    fi
}

# Download a file from the repo
download_file() {
    local filename="$1"
    local base_url="$2"
    local url="${base_url}/${filename}"
    
    if curl -fsSL --max-time 10 "$url" -o "/tmp/$filename"; then
        log_info "✓ Downloaded $filename"
        return 0
    else
        log_error "Failed to download $filename from $url"
        return 1
    fi
}

# Stop existing service if running
stop_existing() {
    if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
        log_info "Stopping existing $SERVICE_NAME service..."
        systemctl stop $SERVICE_NAME
    fi
}

# Create installation directory
setup_directory() {
    mkdir -p $INSTALL_DIR
    log_info "✓ Installation directory: $INSTALL_DIR"
}

# Download and install files from GitHub
install_files() {
    local base_url
    base_url=$(get_base_url)
    
    log_step "Downloading files from GitHub..."
    echo "  Repository: ${REPO_OWNER}/${REPO_NAME}"
    echo "  Version:    ${REPO_BRANCH}"
    echo ""
    
    # Download exporter script
    if ! download_file "pwrstat_exporter.py" "$base_url"; then
        log_error "Failed to download exporter. Check your internet connection and repo access."
        exit 1
    fi
    mv "/tmp/pwrstat_exporter.py" "$INSTALL_DIR/pwrstat_exporter.py"
    chmod +x "$INSTALL_DIR/pwrstat_exporter.py"
    
    # Download systemd service file
    if ! download_file "pwrstat-exporter.service" "$base_url"; then
        log_error "Failed to download service file."
        exit 1
    fi
    mv "/tmp/pwrstat-exporter.service" "/etc/systemd/system/${SERVICE_NAME}.service"
    
    log_info "✓ Files installed to $INSTALL_DIR"
}

# Configure sudo for pwrstat
configure_sudo() {
    log_step "Configuring passwordless sudo for pwrstat..."
    
    cat > $SUDOERS_FILE << EOF
# Allow pwrstat command without password for pwrstat-exporter service
ALL ALL=(ALL) NOPASSWD: ${PWRSTAT_PATH}
EOF
    chmod 440 $SUDOERS_FILE
    log_info "✓ Sudoers configured"
}

# Update systemd service to use correct pwrstat path
update_service_pwrstat_path() {
    if [[ "$PWRSTAT_PATH" != "/usr/bin/pwrstat" ]]; then
        log_info "Updating service file with custom pwrstat path: $PWRSTAT_PATH"
        sed -i "s|/usr/bin/pwrstat|${PWRSTAT_PATH}|g" "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    fi
}

# Enable and start service
start_service() {
    log_step "Enabling and starting $SERVICE_NAME service..."
    
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
    
    # Wait for service to start
    sleep 2
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "✓ Service is running"
    else
        log_error "Service failed to start"
        log_info "Check logs: journalctl -u $SERVICE_NAME -e"
        exit 1
    fi
}

# Verify exporter is working
verify() {
    log_step "Verifying exporter..."
    
    sleep 2
    
    if curl -sf http://localhost:$EXPORTER_PORT/metrics > /dev/null; then
        log_info "✓ Metrics available at http://localhost:$EXPORTER_PORT/metrics"
        echo ""
        echo "Sample metrics:"
        echo "─────────────────────────────────────"
        curl -s http://localhost:$EXPORTER_PORT/metrics | grep -E '^pwrstat_(state|battery|load_watts)' | head -5
        echo "─────────────────────────────────────"
    else
        log_error "Exporter not responding on port $EXPORTER_PORT"
        log_info "Check logs: journalctl -u $SERVICE_NAME -e"
        exit 1
    fi
}

# Print next steps
print_next_steps() {
    echo ""
    log_info "═══════════════════════════════════════════════════"
    log_info "  ✅ pwrstat-node-exporter installed! 🎉"
    log_info "═══════════════════════════════════════════════════"
    echo ""
    echo "Service Management:"
    echo "  Status:   systemctl status $SERVICE_NAME"
    echo "  Stop:     systemctl stop $SERVICE_NAME"
    echo "  Start:    systemctl start $SERVICE_NAME"
    echo "  Logs:     journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "Metrics:"
    echo "  http://localhost:$EXPORTER_PORT/metrics"
    echo "  http://localhost:$EXPORTER_PORT/health"
    echo ""
    echo "Configure Prometheus Scrape:"
    echo "  Add to kube-prometheus-stack values:"
    echo ""
    echo "  prometheus:"
    echo "    prometheusSpec:"
    echo "      additionalScrapeConfigs:"
    echo "        - job_name: 'pwrstat-exporter'"
    echo "          scrape_interval: 30s"
    echo "          static_configs:"
    echo "            - targets: ['<NODE_IP>:$EXPORTER_PORT']"
    echo ""
    log_info "═══════════════════════════════════════════════════"
}

# Main
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   pwrstat-node-exporter Installer               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check pwrstat FIRST - this is the critical dependency
    check_pwrstat
    check_python
    stop_existing
    setup_directory
    install_files
    configure_sudo
    update_service_pwrstat_path
    start_service
    verify
    print_next_steps
}

main "$@"
