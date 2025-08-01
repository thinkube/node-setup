# Thinkube Node Setup

Bootstrap script for preparing Ubuntu nodes for remote Thinkube installation via ZeroTier.

## Quick Start

Run this command on each Ubuntu node you want to prepare for Thinkube:

```bash
curl -sSL https://raw.githubusercontent.com/thinkube/node-setup/main/bootstrap.sh | bash
```

## What This Does

1. **Auto-detects network configuration** from your Ubuntu setup
2. **Installs ZeroTier** and joins your private network
3. **Configures your existing user** for Ansible automation
4. **Prepares the node** for remote Thinkube installation

## Prerequisites

- Fresh Ubuntu 24.04 installation (arm64 or amd64)
- Network connectivity
- ZeroTier Network ID (create one at [my.zerotier.com](https://my.zerotier.com))
- ZeroTier API Token (from Account settings)

## Usage

### Step 1: Prepare Your ZeroTier Network

1. Create a ZeroTier network at [my.zerotier.com](https://my.zerotier.com)
2. Note your Network ID (looks like: `1234567890abcdef`)
3. Get your API token from Account settings
4. Configure your network:
   - Set IPv4 Auto-Assign to a range like `192.168.191.0/24`
   - Or use Manual assignment for specific IPs

### Step 2: Run Bootstrap on Each Node

```bash
curl -sSL https://raw.githubusercontent.com/thinkube/node-setup/main/bootstrap.sh | bash
```

**Important**: Choose static IPs outside your DHCP range. Common examples:
- If DHCP uses `.100-.199`, use `.10-.99` or `.200-.254`
- If DHCP uses `.1-.100`, use `.150-.254`
- Check your router settings to confirm DHCP range

The script will:
- Check and install OpenSSH if needed
- Auto-detect your current network settings (shows DHCP info)
- Configure a static IP address (you choose one outside DHCP range)
- Use your existing Ubuntu user for automation
- Install and configure ZeroTier

You'll be asked for:
- Static IP address (must be outside your DHCP range)
- ZeroTier Network ID
- ZeroTier API Token  
- Desired ZeroTier IP for this node

### Step 3: Verify Setup

After bootstrap completes, verify:

```bash
# Check ZeroTier status
sudo zerotier-cli status

# Check network membership
sudo zerotier-cli listnetworks

# Test connectivity from another ZeroTier node
ping <zerotier-ip>
```

### Step 4: Remote Installation

From a machine with ZeroTier access:

1. Join the same ZeroTier network
2. Run the Thinkube installer
3. Use the ZeroTier IPs for your nodes
4. Use the same username you configured during bootstrap
5. Complete installation remotely

## Manual Setup

If you prefer to run commands manually, see [docs/manual-setup.md](docs/manual-setup.md)

## Troubleshooting

### ZeroTier not connecting?

```bash
# Check service status
sudo systemctl status zerotier-one

# Restart service
sudo systemctl restart zerotier-one

# Check if joined network
sudo zerotier-cli listnetworks
```

### Can't SSH to node?

```bash
# Verify SSH is running
sudo systemctl status ssh

# Check firewall
sudo ufw status

# Verify user exists
id thinkube
```

## Security Notes

- The bootstrap script doesn't store any secrets
- ZeroTier API token is only used during setup
- Creates a dedicated `thinkube` user for Ansible
- All ZeroTier traffic is encrypted
- Nodes must be explicitly authorized in your network

## Support

For issues or questions:
- [GitHub Issues](https://github.com/thinkube/node-setup/issues)
- [Thinkube Documentation](https://github.com/cmxela/thinkube)

## License

MIT License - See [LICENSE](LICENSE) file