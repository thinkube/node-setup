#!/bin/bash
# Thinkube Node Bootstrap Script
# Prepares Ubuntu nodes for Thinkube installation
# 
# Usage: 
#   With ZeroTier:    curl -sSL https://raw.githubusercontent.com/thinkube/node-setup/main/bootstrap.sh | sudo bash
#   Without ZeroTier: curl -sSL https://raw.githubusercontent.com/thinkube/node-setup/main/bootstrap.sh | sudo bash -s -- --no-zerotier

set -e

# Script version
VERSION="1.1.1"

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

    curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' | gpg --dearmor > /usr/share/keyrings/zerotier.gpg
    echo 'deb [signed-by=/usr/share/keyrings/zerotier.gpg] https://download.zerotier.com/debian/buster buster main' > /etc/apt/sources.list.d/zerotier.list
    apt-get update
    apt-get install -y zerotier-one

    systemctl enable zerotier-one
    systemctl start zerotier-one
    sleep 5

    # Join network
    zerotier-cli join "$ZEROTIER_NETWORK_ID"
    ZEROTIER_NODE_ID=$(zerotier-cli info | cut -d' ' -f3)

    # Phase 4: Authorize node
    log_step "Authorizing node in ZeroTier"

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
      }')

    if [[ $? -eq 0 ]]; then
        log_info "Node authorized successfully"
    else
        log_warn "Failed to authorize automatically - please authorize manually in ZeroTier Central"
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
    echo "ZeroTier Status:"
    zerotier-cli listnetworks
    echo
    echo "Next Steps:"
    echo "1. Verify ZeroTier shows 'OK' status above"
    echo "2. From a ZeroTier-connected machine:"
    echo "   ssh $SYSTEM_USER@$ZEROTIER_IP"
    echo "3. Run Thinkube installer using this user"
else
    echo
    echo "Next Steps:"
    echo "1. From a machine on the same network:"
    echo "   ssh $SYSTEM_USER@$STATIC_IP"
    echo "2. Run Thinkube installer"
fi
echo