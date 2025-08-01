#!/bin/bash
# Thinkube Node Bootstrap Script
# Prepares Ubuntu nodes for Thinkube installation
# 
# Usage: 
#   With ZeroTier:    curl -sSL https://raw.githubusercontent.com/thinkube/node-setup/main/bootstrap.sh | sudo bash
#   Without ZeroTier: curl -sSL https://raw.githubusercontent.com/thinkube/node-setup/main/bootstrap.sh | sudo bash -s -- --no-zerotier

set -e

# Script version
VERSION="0.2.1"

# Function to read input that works with piped scripts
read_input() {
    local prompt="$1"
    local varname="$2"
    local value
    
    echo -n "$prompt"
    if [ -t 0 ]; then
        read value
    else
        read value </dev/tty
    fi
    
    eval "$varname='$value'"
}

# Function to read password (hidden input)
read_password() {
    local prompt="$1"
    local varname="$2"
    local value
    
    echo -n "$prompt"
    stty -echo 2>/dev/null || true
    if [ -t 0 ]; then
        read value
    else
        read value </dev/tty
    fi
    stty echo 2>/dev/null || true
    echo
    
    eval "$varname='$value'"
}

# Parse arguments
INSTALL_ZEROTIER=true
for arg in "$@"; do
    case $arg in
        --no-zerotier)
            INSTALL_ZEROTIER=false
            shift
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "\n${BLUE}==>${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Check Ubuntu version
if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    log_error "This script only supports Ubuntu Linux"
    exit 1
fi

UBUNTU_VERSION=$(lsb_release -rs)
if [[ ! "$UBUNTU_VERSION" =~ ^24\.04$ ]]; then
    log_error "This script requires Ubuntu 24.04. You have $UBUNTU_VERSION"
    exit 1
fi

# Auto-discover network settings
log_step "Auto-discovering network configuration"

# Get default interface
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$DEFAULT_INTERFACE" ]; then
    log_error "Could not detect default network interface"
    exit 1
fi

# Get current IP
CURRENT_IP=$(ip -4 addr show "$DEFAULT_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$CURRENT_IP" ]; then
    log_error "Could not detect current IP address"
    exit 1
fi

# Get gateway
GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -z "$GATEWAY_IP" ]; then
    log_error "Could not detect gateway IP"
    exit 1
fi

# Get subnet prefix
SUBNET_PREFIX=$(ip -4 addr show "$DEFAULT_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d'/' -f2 | head -1)
SUBNET_PREFIX=${SUBNET_PREFIX:-24}

# Get current DNS
CURRENT_DNS=$(systemd-resolve --status | grep "DNS Servers" | head -1 | awk '{print $3}')
CURRENT_DNS=${CURRENT_DNS:-8.8.8.8}

# Get hostname
CURRENT_HOSTNAME=$(hostname)

# Get the user who invoked sudo (or current user if not sudo)
if [ -n "$SUDO_USER" ]; then
    SYSTEM_USER="$SUDO_USER"
else
    # If not run with sudo, get the first non-root user with a home directory
    SYSTEM_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home\// {print $1}' | head -1)
fi

if [ -z "$SYSTEM_USER" ]; then
    log_error "Could not detect system user"
    exit 1
fi

# Welcome message
clear
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Thinkube Node Bootstrap v${VERSION}              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo
if [ "$INSTALL_ZEROTIER" = true ]; then
    echo "Mode: With ZeroTier (for remote access)"
else
    echo "Mode: Local only (no ZeroTier)"
fi
echo

log_info "Detected configuration:"
echo "  Hostname:     $CURRENT_HOSTNAME"
echo "  Interface:    $DEFAULT_INTERFACE"
echo "  IP Address:   $CURRENT_IP/$SUBNET_PREFIX"
echo "  Gateway:      $GATEWAY_IP"
echo "  DNS Server:   $CURRENT_DNS"
echo "  System User:  $SYSTEM_USER"
echo

# Check if OpenSSH is installed
log_step "Checking SSH"
if ! command -v sshd &> /dev/null; then
    log_info "Installing OpenSSH Server..."
    apt-get update
    apt-get install -y openssh-server openssh-client
    systemctl enable ssh
    systemctl start ssh
else
    log_info "OpenSSH Server is already installed"
fi

# Static IP configuration
log_step "Network Configuration"
echo "Current IP from DHCP: $CURRENT_IP (for reference only)"
echo
echo "You need to assign a static IP outside your DHCP range."
echo "Common static IP ranges: 192.168.1.10-30, 192.168.1.200-254"
echo
read_input "Enter static IP address for this node: " STATIC_IP
while ! [[ "$STATIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
    log_error "Invalid IP format"
    read_input "Enter static IP address for this node: " STATIC_IP
done

# Backup existing netplan
log_info "Backing up network configuration..."
if [ -d /etc/netplan ]; then
    cp -a /etc/netplan /etc/netplan.backup.$(date +%Y%m%d-%H%M%S)
fi

# Configure static network
log_info "Configuring static IP: $STATIC_IP"
cat > /etc/netplan/01-thinkube.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${DEFAULT_INTERFACE}:
      addresses:
        - ${STATIC_IP}/${SUBNET_PREFIX}
      routes:
        - to: default
          via: ${GATEWAY_IP}
      nameservers:
        addresses:
          - ${CURRENT_DNS}
          - 8.8.8.8
EOF

# Set proper permissions for netplan config
chmod 600 /etc/netplan/01-thinkube.yaml

log_info "Applying network configuration..."
log_warn "Your connection may drop when the IP changes from $CURRENT_IP to $STATIC_IP"
echo "If disconnected, reconnect using: ssh $SYSTEM_USER@$STATIC_IP"
echo
read_input "Press Enter to continue..." _dummy 

netplan apply

# Verify connectivity
sleep 3
if ! ping -c 1 8.8.8.8 &>/dev/null; then
    log_warn "Network connectivity test failed. You may need to reconnect using the new IP: $STATIC_IP"
fi

# ZeroTier configuration (if enabled)
if [ "$INSTALL_ZEROTIER" = true ]; then
    log_step "ZeroTier Configuration"
    echo "You'll need:"
    echo "  - ZeroTier Network ID (16 characters)"
    echo "  - ZeroTier API Token (from my.zerotier.com)"
    echo

    read_input "ZeroTier Network ID: " ZEROTIER_NETWORK_ID
    while [[ ${#ZEROTIER_NETWORK_ID} -ne 16 ]]; do
        log_error "Network ID must be 16 characters"
        read_input "ZeroTier Network ID: " ZEROTIER_NETWORK_ID
    done

    read_password "ZeroTier API Token: " ZEROTIER_API_TOKEN
    while [[ -z "$ZEROTIER_API_TOKEN" ]]; do
        log_error "API Token cannot be empty"
        read_password "ZeroTier API Token: " ZEROTIER_API_TOKEN
    done

    read_input "ZeroTier IP for this node: " ZEROTIER_IP
    while ! [[ "$ZEROTIER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
        log_error "Invalid IP format"
        read_input "ZeroTier IP for this node: " ZEROTIER_IP
    done
fi

# Phase 1: Install required packages
log_step "Installing required packages"

apt-get update
apt-get install -y \
    curl \
    wget \
    gnupg \
    apt-transport-https \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    ufw

# Phase 2: Configure firewall
log_step "Configuring firewall"

ufw allow ssh
ufw allow 9993/udp  # ZeroTier
echo "y" | ufw enable || true

# Phase 3: Install ZeroTier (if enabled)
if [ "$INSTALL_ZEROTIER" = true ]; then
    log_step "Installing ZeroTier"

    # Check if ZeroTier is already installed but broken
    if command -v zerotier-cli &> /dev/null; then
        if ! zerotier-cli status &> /dev/null; then
            log_warn "Detected broken ZeroTier installation, cleaning up..."
            systemctl stop zerotier-one 2>/dev/null || true
            systemctl disable zerotier-one 2>/dev/null || true
            apt-get remove --purge zerotier-one -y 2>/dev/null || true
            rm -rf /var/lib/zerotier-one
            rm -f /etc/apt/sources.list.d/zerotier.list
            rm -f /usr/share/keyrings/zerotier.gpg
            apt-get update
        fi
    fi
    
    # Use the official installation method
    log_info "Installing ZeroTier using official installer..."
    curl -s https://install.zerotier.com | bash || {
        log_error "Failed to install ZeroTier using official installer"
        log_info "Trying alternative method..."
        
        # Alternative method if the official installer fails
        curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' | gpg --dearmor > /usr/share/keyrings/zerotier.gpg
        echo 'deb [signed-by=/usr/share/keyrings/zerotier.gpg] https://download.zerotier.com/debian/jammy jammy main' > /etc/apt/sources.list.d/zerotier.list
        apt-get update
        apt-get install -y zerotier-one
    }
    
    # Give the service time to create its files
    sleep 2
    
    # Enable and start the service
    systemctl daemon-reload
    systemctl enable zerotier-one
    systemctl start zerotier-one || {
        log_error "Failed to start ZeroTier service"
        log_info "Trying to diagnose the issue..."
        systemctl status zerotier-one --no-pager || true
        journalctl -xeu zerotier-one --no-pager -n 20 || true
        exit 1
    }
    
    # Wait for service to be ready
    log_info "Waiting for ZeroTier service to start..."
    for i in {1..10}; do
        if systemctl is-active --quiet zerotier-one; then
            log_info "ZeroTier service is active"
            break
        fi
        sleep 1
    done

    # Join network
    log_info "Joining ZeroTier network..."
    zerotier-cli join "$ZEROTIER_NETWORK_ID" || {
        log_error "Failed to join ZeroTier network"
        exit 1
    }
    
    # Get node ID
    ZEROTIER_NODE_ID=$(zerotier-cli info | cut -d' ' -f3)
    log_info "ZeroTier Node ID: $ZEROTIER_NODE_ID"

    # Phase 4: Authorize node
    log_step "Authorizing node in ZeroTier"

    log_info "Attempting to authorize node with IP ${ZEROTIER_IP}..."
    
    # Use curl with separate output for body and headers
    AUTH_RESPONSE=$(curl -s -X POST "https://api.zerotier.com/api/v1/network/${ZEROTIER_NETWORK_ID}/member/${ZEROTIER_NODE_ID}" \
      -H "Authorization: Bearer ${ZEROTIER_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'${CURRENT_HOSTNAME}'",
        "description": "Thinkube node",
        "config": {
          "authorized": true,
          "ipAssignments": ["'${ZEROTIER_IP}'"],
          "noAutoAssignIps": true
        }
      }' \
      -w "\nHTTP_STATUS_CODE:%{http_code}")

    # Extract status code
    HTTP_CODE=$(echo "$AUTH_RESPONSE" | grep "HTTP_STATUS_CODE:" | cut -d: -f2)
    RESPONSE_BODY=$(echo "$AUTH_RESPONSE" | sed '/HTTP_STATUS_CODE:/d')

    # Check if successful (200 or 201)
    if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "201" ]]; then
        log_info "✓ Node authorized successfully with IP ${ZEROTIER_IP}"
        ZEROTIER_AUTHORIZED=true
        
        # Wait a moment for the authorization to propagate
        sleep 3
        
        # Verify the node is actually authorized
        if zerotier-cli listnetworks | grep -q "OK"; then
            log_info "✓ ZeroTier network status confirmed as OK"
        else
            log_warn "Authorization successful but network still showing REQUESTING_CONFIGURATION"
            log_info "This is normal - it may take a few moments to update"
        fi
    else
        log_error "Failed to authorize node automatically (HTTP ${HTTP_CODE})"
        if [[ -n "$RESPONSE_BODY" ]]; then
            log_info "Response: ${RESPONSE_BODY}"
        fi
        log_warn "You must manually authorize this node in ZeroTier Central"
        log_warn "Node ID: ${ZEROTIER_NODE_ID}"
        ZEROTIER_AUTHORIZED=false
    fi
fi

# Phase 5: Configure user for Ansible
log_step "Configuring $SYSTEM_USER for Ansible access"

# Ensure user is in sudo group
usermod -aG sudo "$SYSTEM_USER" 2>/dev/null || true

# Configure passwordless sudo for the user
echo "$SYSTEM_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SYSTEM_USER"
chmod 0440 "/etc/sudoers.d/$SYSTEM_USER"

# Ensure SSH directory exists
USER_HOME=$(getent passwd "$SYSTEM_USER" | cut -d: -f6)
mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
chown "$SYSTEM_USER:$SYSTEM_USER" "$USER_HOME/.ssh"

# Generate SSH key if it doesn't exist
if [ ! -f "$USER_HOME/.ssh/id_ed25519" ]; then
    sudo -u "$SYSTEM_USER" ssh-keygen -t ed25519 -f "$USER_HOME/.ssh/id_ed25519" -N "" -C "$SYSTEM_USER@$CURRENT_HOSTNAME"
fi

# Phase 6: Save configuration
log_step "Saving configuration"

cat > /etc/thinkube-bootstrap.conf << EOF
# Thinkube Bootstrap Configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
HOSTNAME=${CURRENT_HOSTNAME}
INTERFACE=${DEFAULT_INTERFACE}
STATIC_IP=${STATIC_IP}
SUBNET_PREFIX=${SUBNET_PREFIX}
GATEWAY=${GATEWAY_IP}
DNS_SERVER=${CURRENT_DNS}
SYSTEM_USER=${SYSTEM_USER}
ZEROTIER_ENABLED=${INSTALL_ZEROTIER}
ZEROTIER_NETWORK_ID=${ZEROTIER_NETWORK_ID:-none}
ZEROTIER_NODE_ID=${ZEROTIER_NODE_ID:-none}
ZEROTIER_IP=${ZEROTIER_IP:-none}
BOOTSTRAP_VERSION=${VERSION}
EOF

chmod 600 /etc/thinkube-bootstrap.conf

# Final verification
log_step "Verification"

# Wait for ZeroTier if installed
if [ "$INSTALL_ZEROTIER" = true ]; then
    sleep 10
    # Set default if not set
    ZEROTIER_AUTHORIZED=${ZEROTIER_AUTHORIZED:-false}
fi

# Show status
echo
echo "╔══════════════════════════════════════════════════════╗"
echo "║            ✅ Bootstrap Complete!                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo
echo "Node Information:"
echo "  Hostname:         $CURRENT_HOSTNAME"
echo "  Static IP:        $STATIC_IP"
echo "  SSH User:         $SYSTEM_USER"

if [ "$INSTALL_ZEROTIER" = true ]; then
    echo "  ZeroTier IP:      $ZEROTIER_IP"
    echo "  ZeroTier Node:    $ZEROTIER_NODE_ID"
    echo
    echo "ZeroTier Network Status:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get and parse the network status
    NETWORK_STATUS=$(zerotier-cli listnetworks 2>/dev/null | grep "$ZEROTIER_NETWORK_ID" || echo "")
    
    if [[ -n "$NETWORK_STATUS" ]]; then
        # Parse the status (it's the 6th field)
        STATUS_FIELD=$(echo "$NETWORK_STATUS" | awk '{print $6}')
        ASSIGNED_IP=$(echo "$NETWORK_STATUS" | awk '{print $9}')
        
        case "$STATUS_FIELD" in
            "OK")
                log_info "✅ Network Status: CONNECTED AND AUTHORIZED"
                log_info "✅ Assigned IP: $ASSIGNED_IP"
                ;;
            "REQUESTING_CONFIGURATION")
                log_warn "⏳ Network Status: REQUESTING_CONFIGURATION"
                log_warn "   Node needs to be authorized in ZeroTier Central"
                ;;
            "ACCESS_DENIED")
                log_error "❌ Network Status: ACCESS_DENIED"
                log_error "   Node was not authorized or was deauthorized"
                ;;
            *)
                log_warn "⚠️  Network Status: $STATUS_FIELD"
                ;;
        esac
    else
        log_error "Failed to get ZeroTier network status"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo "Next Steps:"
    if [ "$ZEROTIER_AUTHORIZED" = true ]; then
        echo "1. This node is ready for Thinkube installation"
        echo "2. From your installer machine (with ZeroTier access):"
        echo "   - Run the Thinkube installer"
        echo "   - When discovering nodes, use ZeroTier IP: $ZEROTIER_IP"
        echo "   - SSH user: $SYSTEM_USER"
    else
        echo "1. Authorize this node in ZeroTier Central:"
        echo "   - Go to https://my.zerotier.com"
        echo "   - Find node ID: $ZEROTIER_NODE_ID"
        echo "   - Click the checkbox to authorize"
        echo "   - Assign IP: $ZEROTIER_IP"
        echo "2. Once authorized, from your installer machine:"
        echo "   - Run the Thinkube installer"
        echo "   - Use this node's ZeroTier IP: $ZEROTIER_IP"
    fi
else
    echo
    echo "Next Steps:"
    echo "1. From a machine on the same network:"
    echo "   ssh $SYSTEM_USER@$STATIC_IP"
    echo "2. Run Thinkube installer"
fi
echo