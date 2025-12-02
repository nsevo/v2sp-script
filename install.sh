#!/bin/bash
#
# v2sp installer - Simplified version
# All logic moved to Go binary
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# Helper functions
error() { echo -e "${RED}✗${PLAIN} $1"; exit 1; }
success() { echo -e "${GREEN}✓${PLAIN} $1"; }
info() { echo -e "${CYAN}ℹ${PLAIN} $1"; }
warn() { echo -e "${YELLOW}⚠${PLAIN} $1"; }

# Check root
[[ $EUID -ne 0 ]] && error "Root privileges required"

# Detect OS and architecture
detect_system() {
    # OS detection
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        error "Unsupported operating system"
    fi

    # Architecture detection
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) ARCH="64" ;;
        aarch64|arm64) ARCH="arm64-v8a" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    info "Detected: $OS ($ARCH)"
}

# Install dependencies
install_deps() {
    info "Installing dependencies..."
    
    case "$OS" in
        ubuntu|debian)
            apt-get update -qq >/dev/null 2>&1
            apt-get install -qq -y wget curl unzip >/dev/null 2>&1
            ;;
        centos|rhel|fedora|rocky|alma)
            yum install -y -q wget curl unzip >/dev/null 2>&1
            ;;
        arch)
            pacman -Sy --noconfirm --quiet wget curl unzip >/dev/null 2>&1
            ;;
        alpine)
            apk add --quiet wget curl unzip >/dev/null 2>&1
            ;;
    esac
    
    success "Dependencies installed"
}

# Download v2sp
download_v2sp() {
    VERSION=${1:-latest}
    
    info "Fetching v2sp ${VERSION}..."
    
    # Get latest version if not specified
    if [[ "$VERSION" == "latest" ]]; then
        VERSION=$(curl -fsSL https://api.github.com/repos/nsevo/v2sp/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [[ -z "$VERSION" ]] && error "Failed to get latest version"
    fi
    
    # Download URL
    URL="https://github.com/nsevo/v2sp/releases/download/${VERSION}/v2sp-linux-${ARCH}.zip"
    
    # Download
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    if ! wget -q --show-progress "$URL" -O v2sp.zip; then
        error "Download failed"
    fi
    
    success "Downloaded v2sp ${VERSION}"
    
    # Extract
    info "Installing..."
    unzip -q v2sp.zip
    
    # Install binary
    mkdir -p /usr/local/v2sp
    mv v2sp /usr/local/v2sp/
    chmod +x /usr/local/v2sp/v2sp
    
    # Install management script (symlink)
    ln -sf /usr/local/v2sp/v2sp /usr/bin/v2sp
    
    # Copy geo files
    [[ -f geoip.dat ]] && cp geoip.dat /etc/v2sp/ 2>/dev/null || true
    [[ -f geosite.dat ]] && cp geosite.dat /etc/v2sp/ 2>/dev/null || true
    
    # Cleanup
    cd - >/dev/null
    rm -rf "$TMP_DIR"
    
    success "v2sp installed"
}

# Setup system (using v2sp binary)
setup_system() {
    info "Setting up system configuration..."
    
    # Use v2sp's built-in system setup
    if ! /usr/local/v2sp/v2sp system setup 2>/dev/null; then
        warn "System setup failed, trying manual setup..."
        
        # Fallback: manual setup
        mkdir -p /etc/v2sp /etc/v2sp/cert
        
        # Create systemd service
        cat > /etc/systemd/system/v2sp.service <<'EOF'
[Unit]
Description=v2sp Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Type=simple
LimitNOFILE=999999
WorkingDirectory=/usr/local/v2sp/
ExecStart=/usr/local/v2sp/v2sp server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable v2sp >/dev/null 2>&1
    fi
    
    success "System configured"
}

# Configure v2sp
configure_v2sp() {
    # Check if config exists
    if [[ -f /etc/v2sp/config.json ]]; then
        warn "Config exists, skipping configuration"
        info "Restarting service..."
        systemctl restart v2sp
        return
    fi
    
    # Ask user
    echo ""
    read -p "$(echo -e ${CYAN}Generate configuration now? [Y/n]:${PLAIN} )" answer
    answer=${answer:-y}
    
    if [[ "${answer,,}" == "y" ]]; then
        # Use v2sp's built-in config wizard
        /usr/local/v2sp/v2sp config init
    else
        info "Skipped configuration"
        info "Generate later with: v2sp config init"
    fi
}

# Main installation flow
main() {
    clear
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "  ${CYAN}v2sp Installer${PLAIN}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo ""
    
    detect_system
    install_deps
    download_v2sp "$1"
    setup_system
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "  ${GREEN}✓ Installation Complete${PLAIN}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo ""
    echo -e "  Quick start:"
    echo -e "    ${CYAN}v2sp${PLAIN}              Interactive menu"
    echo -e "    ${CYAN}v2sp status${PLAIN}       Check status"
    echo -e "    ${CYAN}v2sp config init${PLAIN}  Setup configuration"
    echo ""
    
    configure_v2sp
    
    echo ""
    echo -e "  ${GREEN}All done!${PLAIN} Run ${CYAN}v2sp${PLAIN} to get started."
    echo ""
}

main "$@"
