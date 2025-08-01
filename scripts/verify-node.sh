#!/bin/bash
# Verify node is ready for Thinkube installation

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Thinkube Node Verification"
echo "=========================="
echo

# Check if bootstrap was run
if [ ! -f /etc/thinkube-bootstrap.conf ]; then
    echo -e "${RED}✗${NC} Bootstrap configuration not found"
    echo "  Please run the bootstrap script first"
    exit 1
fi

# Load configuration
source /etc/thinkube-bootstrap.conf

# Function to check status
check_status() {
    local name=$1
    local command=$2
    local expected=$3
    
    echo -n "Checking $name... "
    
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓${NC} OK"
        return 0
    else
        echo -e "${RED}✗${NC} FAILED"
        return 1
    fi
}

# Run checks
ERRORS=0

# System checks
check_status "Hostname" "hostname | grep -q $NODE_HOSTNAME" || ((ERRORS++))
check_status "Network interface" "ip link show $NET_INTERFACE" || ((ERRORS++))
check_status "Static IP" "ip addr show $NET_INTERFACE | grep -q $STATIC_IP" || ((ERRORS++))
check_status "Internet connectivity" "ping -c 1 8.8.8.8" || ((ERRORS++))

# Service checks
check_status "SSH service" "systemctl is-active ssh" || ((ERRORS++))
check_status "ZeroTier service" "systemctl is-active zerotier-one" || ((ERRORS++))

# ZeroTier checks
check_status "ZeroTier network joined" "zerotier-cli listnetworks | grep -q $ZEROTIER_NETWORK_ID" || ((ERRORS++))
check_status "ZeroTier authorized" "zerotier-cli listnetworks | grep -q OK" || ((ERRORS++))

# User checks
if [ -z "$SYSTEM_USER" ]; then
    echo -e "${RED}✗${NC} SYSTEM_USER not set in configuration"
    ((ERRORS++))
else
    check_status "System user exists" "id $SYSTEM_USER" || ((ERRORS++))
    check_status "User sudo access" "sudo -u $SYSTEM_USER sudo -n true" || ((ERRORS++))
    USER_HOME=$(getent passwd "$SYSTEM_USER" | cut -d: -f6)
    check_status "SSH key exists" "test -f $USER_HOME/.ssh/id_ed25519" || ((ERRORS++))
fi

echo
echo "Configuration:"
echo "  Hostname:     $NODE_HOSTNAME"
echo "  Static IP:    $STATIC_IP"
echo "  ZeroTier IP:  $ZEROTIER_IP"
echo "  Network ID:   $ZEROTIER_NETWORK_ID"
echo "  Node ID:      $ZEROTIER_NODE_ID"

echo
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ Node is ready for Thinkube installation${NC}"
    exit 0
else
    echo -e "${RED}❌ Node has $ERRORS issues that need to be fixed${NC}"
    exit 1
fi