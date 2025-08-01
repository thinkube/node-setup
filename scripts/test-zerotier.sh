#!/bin/bash
# Test ZeroTier connectivity between nodes

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "ZeroTier Connectivity Test"
echo "========================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Check ZeroTier status
echo "Local ZeroTier Status:"
zerotier-cli status
echo

echo "Networks:"
zerotier-cli listnetworks
echo

# Get list of other nodes
read -p "Enter ZeroTier IPs of other nodes (space-separated): " -a OTHER_NODES

if [ ${#OTHER_NODES[@]} -eq 0 ]; then
    echo -e "${YELLOW}No other nodes specified${NC}"
    exit 0
fi

echo
echo "Testing connectivity to ${#OTHER_NODES[@]} nodes..."
echo

FAILED=0

for node_ip in "${OTHER_NODES[@]}"; do
    echo -n "Testing $node_ip... "
    
    # Ping test
    if ping -c 3 -W 2 "$node_ip" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Ping OK"
        
        # SSH test
        echo -n "  SSH test... "
        if nc -zv -w 2 "$node_ip" 22 &>/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Port 22 open"
        else
            echo -e "${RED}✗${NC} Port 22 closed"
            ((FAILED++))
        fi
    else
        echo -e "${RED}✗${NC} No response"
        ((FAILED++))
    fi
done

echo
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All nodes are reachable${NC}"
    
    # Show route information
    echo
    echo "ZeroTier routing table:"
    ip route | grep zt
else
    echo -e "${RED}❌ Failed to reach $FAILED nodes${NC}"
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if nodes are authorized in ZeroTier Central"
    echo "2. Verify firewall allows ZeroTier (UDP 9993)"
    echo "3. Check 'zerotier-cli peers' for connection status"
    echo "4. Ensure all nodes are on same ZeroTier network"
fi