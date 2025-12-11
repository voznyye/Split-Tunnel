# WireGuard Split Tunnel - Ansible Automation

Automated WireGuard server installation and configuration via Ansible. No manual server access required!

## Requirements

- Ansible >= 6.0.0
- SSH access to server (key-based or password)
- Python on server (usually pre-installed)

## Install Ansible

### macOS
```bash
brew install ansible
```

### Linux (Ubuntu/Debian)
```bash
sudo apt-get install ansible
```

### Linux (CentOS/RHEL)
```bash
sudo yum install ansible
```

### Via pip
```bash
pip install ansible
```

## Quick Start

### 1. Configure inventory

Copy example inventory:
```bash
cd ansible
cp inventory.yml.example inventory.yml
```

Edit `inventory.yml`:
```yaml
servers:
  hosts:
    wireguard-server:
      ansible_host: YOUR_SERVER_IP  # Your server IP
      ansible_user: root            # SSH user
```

### 2. Install WireGuard server

```bash
ansible-playbook -i inventory.yml playbook.yml
```

Playbook automatically:
- ✅ Installs WireGuard and tools
- ✅ Configures IP forwarding
- ✅ Generates server keys
- ✅ Creates server configuration
- ✅ Configures firewall
- ✅ Opens VoIP ports (SIP/RTP) for CRM calls
- ✅ Starts WireGuard
- ✅ Secures SSH

### 3. Create client configuration

```bash
# With IP addresses for routing
ansible-playbook -i inventory.yml generate-client.yml \
  -e 'client_name=myclient' \
  -e 'allowed_ips=192.168.1.100/32,10.0.0.50/32'

# Without IPs (template for manual editing)
ansible-playbook -i inventory.yml generate-client.yml \
  -e 'client_name=myclient'
```

### 4. Download client configuration

```bash
# Via Ansible
ansible wireguard-server -i inventory.yml -m fetch \
  -a "src=/etc/wireguard/clients/myclient.conf dest=./myclient.conf"

# Or via scp
scp root@YOUR_SERVER:/etc/wireguard/clients/myclient.conf ./
```

## Configuration Variables

Override variables in `inventory.yml` or via `-e`:

### Main Variables

- `server_public_ip` - Server public IP (auto-detected if empty)
- `wireguard_port` - WireGuard port (default: 51820)
- `wireguard_vpn_network` - VPN network (default: 10.0.0.0/24)
- `wireguard_server_vpn_ip` - Server VPN IP (default: 10.0.0.1)
- `wireguard_client_dns` - Client DNS (default: 8.8.8.8)
- `wireguard_interface` - Network interface (auto-detected if not set)

### Security Variables

- `wireguard_enable_ip_forwarding` - Enable IP forwarding (default: true)
- `wireguard_enable_firewall` - Configure firewall (default: true)
- `wireguard_enable_ssh_security` - Configure SSH security (default: true)
- `ssh_max_auth_tries` - Max SSH auth attempts (default: 3)
- `ssh_login_grace_time` - SSH login grace time (default: 30)

### VoIP/CRM Variables

- `wireguard_enable_voip_ports` - Enable VoIP ports for CRM calls (default: true)
- `wireguard_voip_sip_port` - SIP port (default: 5060)
- `wireguard_voip_rtp_start` - RTP port range start (default: 10000)
- `wireguard_voip_rtp_end` - RTP port range end (default: 20000)
- `wireguard_client_mtu` - Client MTU (optional, e.g., 1420 for VoIP. Empty = auto)

## Usage Examples

### Install with custom parameters

```bash
ansible-playbook -i inventory.yml playbook.yml \
  -e 'wireguard_port=51821' \
  -e 'wireguard_client_dns=1.1.1.1'
```

### Create multiple clients

```bash
ansible-playbook -i inventory.yml generate-client.yml \
  -e 'client_name=laptop' -e 'allowed_ips=192.168.1.100/32'

ansible-playbook -i inventory.yml generate-client.yml \
  -e 'client_name=phone' -e 'allowed_ips=192.168.1.101/32'
```

### Create client with VoIP MTU

```bash
ansible-playbook -i inventory.yml generate-client.yml \
  -e 'client_name=crm-client' \
  -e 'allowed_ips=0.0.0.0/0,::/0' \
  -e 'wireguard_client_mtu=1420'
```

### Dry-run check

```bash
ansible-playbook -i inventory.yml playbook.yml --check
```

### Check WireGuard status

```bash
ansible wireguard-server -i inventory.yml -m shell -a "wg show"
```

## File Structure

```
ansible/
├── playbook.yml              # Main server installation playbook
├── generate-client.yml        # Client config generation playbook
├── inventory.yml.example      # Inventory example (YAML)
├── inventory.ini.example      # Inventory example (INI)
├── requirements.txt          # Ansible dependencies
├── config/
│   └── client.conf.j2        # Client config template
└── roles/
    └── wireguard/
        ├── tasks/
        │   └── main.yml      # Installation tasks
        ├── handlers/
        │   └── main.yml      # Event handlers
        ├── templates/
        │   └── wg0.conf.j2   # Server config template
        └── defaults/
            └── main.yml      # Default variables
```

## Troubleshooting

### SSH connection error

Ensure:
- SSH key added to `~/.ssh/authorized_keys` on server
- Or use `-k` for password: `ansible-playbook -i inventory.yml playbook.yml -k`

### "Python not found" error

Install Python on server:
```bash
ansible wireguard-server -i inventory.yml -m raw -a "apt-get install -y python3"
```

### Validate configuration

```bash
# Check playbook syntax
ansible-playbook --syntax-check -i inventory.yml playbook.yml

# Check inventory
ansible-inventory -i inventory.yml --list
```

## Integration

After Ansible installation, you can use regular scripts for client management on the server, or continue using Ansible for full automation.

## See Also

See main [README.md](../README.md) for general project information.
