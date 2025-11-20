# Quick Start Guide

## 1. Install Ansible

```bash
# macOS
brew install ansible

# Ubuntu/Debian
sudo apt-get install ansible

# Or via pip
pip install ansible
```

## 2. Configure Inventory

```bash
cd ansible
cp inventory.yml.example inventory.yml
```

Edit `inventory.yml`:
```yaml
servers:
  hosts:
    wireguard-server:
      ansible_host: YOUR_SERVER_IP  # ← Your server IP
      ansible_user: root            # ← SSH user
```

## 3. Install WireGuard Server

```bash
ansible-playbook -i inventory.yml playbook.yml
```

## 4. Create Client

```bash
ansible-playbook -i inventory.yml generate-client.yml \
  -e 'client_name=myclient' \
  -e 'allowed_ips=192.168.1.100/32,10.0.0.50/32'
```

## 5. Download Configuration

```bash
scp root@YOUR_SERVER:/etc/wireguard/clients/myclient.conf ./
```

Done! Now install the configuration on your client.
