# Manual Node Setup Guide

If you prefer to set up nodes manually instead of using the bootstrap script, follow these steps.

## Prerequisites

- Ubuntu 24.04 (arm64 or amd64)
- Root or sudo access
- Network connectivity

## Step 1: Configure Static Networking

Edit your netplan configuration:

```bash
sudo nano /etc/netplan/01-network.yaml
```

Add your network configuration:

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:  # Replace with your interface name
      addresses:
        - 192.168.1.100/24  # Your static IP
      routes:
        - to: default
          via: 192.168.1.1  # Your gateway
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

Apply the configuration:

```bash
sudo netplan apply
```

## Step 2: Set Hostname

```bash
sudo hostnamectl set-hostname your-node-name
echo "127.0.1.1 your-node-name" | sudo tee -a /etc/hosts
```

## Step 3: Install Required Packages

```bash
sudo apt update
sudo apt install -y \
    curl \
    wget \
    gnupg \
    apt-transport-https \
    ca-certificates \
    openssh-server \
    python3 \
    python3-pip \
    python3-venv \
    sudo \
    ufw \
    net-tools
```

## Step 4: Configure SSH

```bash
# Enable SSH
sudo systemctl enable ssh
sudo systemctl start ssh

# Configure firewall
sudo ufw allow ssh
sudo ufw allow 9993/udp  # For ZeroTier
sudo ufw enable
```

## Step 5: Install ZeroTier

```bash
# Add ZeroTier GPG key
curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' | \
  sudo gpg --dearmor -o /usr/share/keyrings/zerotier.gpg

# Add repository
echo 'deb [signed-by=/usr/share/keyrings/zerotier.gpg] https://download.zerotier.com/debian/buster buster main' | \
  sudo tee /etc/apt/sources.list.d/zerotier.list

# Install ZeroTier
sudo apt update
sudo apt install -y zerotier-one

# Enable and start service
sudo systemctl enable zerotier-one
sudo systemctl start zerotier-one
```

## Step 6: Join ZeroTier Network

```bash
# Join network
sudo zerotier-cli join YOUR_NETWORK_ID

# Get your node ID
sudo zerotier-cli info
```

## Step 7: Authorize Node in ZeroTier Central

### Option A: Via Web Interface

1. Log in to [my.zerotier.com](https://my.zerotier.com)
2. Go to your network
3. Find your node in the Members section
4. Check the "Auth?" checkbox
5. Assign a static IP in the "Managed IPs" field

### Option B: Via API

```bash
# Get your node ID
NODE_ID=$(sudo zerotier-cli info | cut -d' ' -f3)

# Authorize and assign IP
curl -X POST "https://api.zerotier.com/api/v1/network/YOUR_NETWORK_ID/member/$NODE_ID" \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "your-node-name",
    "config": {
      "authorized": true,
      "ipAssignments": ["192.168.191.10"],
      "noAutoAssignIps": true
    }
  }'
```

## Step 8: Create Ansible User

```bash
# Choose your username for automation
ANSIBLE_USER="your_chosen_username"  # Replace with your actual username

# Create user
sudo useradd -m -s /bin/bash -c "Ansible Automation User" $ANSIBLE_USER

# Add to sudo group
sudo usermod -aG sudo $ANSIBLE_USER

# Configure passwordless sudo
echo "$ANSIBLE_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$ANSIBLE_USER
sudo chmod 0440 /etc/sudoers.d/$ANSIBLE_USER

# Create SSH directory
sudo mkdir -p /home/$ANSIBLE_USER/.ssh
sudo chmod 700 /home/$ANSIBLE_USER/.ssh

# Generate SSH key
sudo -u $ANSIBLE_USER ssh-keygen -t ed25519 -f /home/$ANSIBLE_USER/.ssh/id_ed25519 -N ""

# Fix permissions
sudo chown -R $ANSIBLE_USER:$ANSIBLE_USER /home/$ANSIBLE_USER/.ssh
```

## Step 9: Verify Setup

Check that everything is working:

```bash
# Check hostname
hostname

# Check network
ip addr show

# Check ZeroTier
sudo zerotier-cli listnetworks

# Check SSH
sudo systemctl status ssh

# Check user
id $ANSIBLE_USER
```

## Step 10: Test Remote Access

From another machine on the ZeroTier network:

```bash
# Test connectivity
ping YOUR_ZEROTIER_IP

# Test SSH
ssh your_username@YOUR_ZEROTIER_IP
```

## Troubleshooting

### ZeroTier not connecting

```bash
# Check service
sudo systemctl status zerotier-one

# Restart service
sudo systemctl restart zerotier-one

# Check peers
sudo zerotier-cli peers

# Leave and rejoin network
sudo zerotier-cli leave YOUR_NETWORK_ID
sudo zerotier-cli join YOUR_NETWORK_ID
```

### Network issues

```bash
# Check routes
ip route

# Check DNS
nslookup google.com

# Check firewall
sudo ufw status verbose
```

### SSH issues

```bash
# Check SSH config
sudo sshd -t

# Check logs
sudo journalctl -u ssh -f

# Regenerate host keys if needed
sudo ssh-keygen -A
```