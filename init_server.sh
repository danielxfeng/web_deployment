#!/bin/bash

# This script is to initialize a web server.
# - It installs Docker and docker-compose-plugin.
# - It sets up SSH with a custom port and adds a public key for CI/CD.
# - It configures a firewall with UFW.
# - It disables root login and password authentication for SSH.

# Required .env variables:
# - CICD_PUB_KEY: SSH public key for CI/CD access
# - SSH_PORT: Custom SSH port (1024-65535)

set -euo pipefail  # Exit on error

#----------- Setup logging
LOG_FILE="/var/log/server-init.log"
exec 1> >(tee -a "$LOG_FILE") 2>&1

echo "Cool, let's initialize the server..."

#----------- Parsing and error handling
if [[ ! -f ".env" ]]; then
  echo "ERROR: .env file not found."
  exit 1
fi

source .env  # Load environment variables

# Validate environment variables
if [[ -z "${CICD_PUB_KEY:-}" ]]; then
    echo "ERROR: CICD_PUB_KEY not set in .env"
    exit 1
fi

# Validate CICD_PUB_KEY format
if [[ -z "${SSH_PORT:-}" ]]; then
    echo "ERROR: SSH_PORT not set in .env"
    exit 1
fi

# Validate SSH port range
if [[ "$SSH_PORT" -lt 1024 || "$SSH_PORT" -gt 65535 ]]; then
    echo "ERROR: SSH_PORT must be between 1024-65535"
    exit 1
fi

# Validate SSH key format
if ! echo "$CICD_PUB_KEY" | ssh-keygen -l -f - &>/dev/null; then
    echo "ERROR: Invalid SSH public key format"
    exit 1
fi

# Check idempotency
if [[ -f "/var/log/server-init-complete" ]]; then
  echo "Server appears to already be initialized."
  [[ "${1:-}" != "--force" ]] && exit 0
fi

#----------- Update and install dependencies
echo "The system is updating, if restarted, please run this script again."
sudo apt update && sudo apt upgrade -y
sudo apt install -y netcat-openbsd

# Install Docker
if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
else
  echo "Docker already installed, skipping."
fi

# Install docker-compose-plugin
if ! dpkg -s docker-compose-plugin &> /dev/null; then
  echo "docker-compose-plugin not found. Installing..."
  sudo apt install -y docker-compose-plugin
else
  echo "docker-compose-plugin already installed, skipping."
fi

# Add current user to docker group
if ! groups $USER | grep -q docker; then
  echo "Adding user to docker group..."
  sudo usermod -aG docker $USER
  echo "Note: You'll need to log out and back in for docker group changes to take effect"
fi

#----------- SSH hardening

# SSH key setup
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Ensure authorized_keys file exists
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Add CI/CD public key
if ! grep -Fxq "$CICD_PUB_KEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$CICD_PUB_KEY" >> ~/.ssh/authorized_keys
    echo "Added CI/CD public key"
else
    echo "CI/CD public key already exists"
fi

# Backup SSH config before modifying
BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
sudo cp /etc/ssh/sshd_config "$BACKUP_FILE"

# Rollback function for SSH configuration
rollback_ssh() {
    if [[ -n "${BACKUP_FILE:-}" && -f "$BACKUP_FILE" ]]; then
        echo "Rolling back SSH configuration..."
        sudo cp "$BACKUP_FILE" /etc/ssh/sshd_config
        sudo systemctl restart sshd
    fi
}

trap 'echo "ERROR: Script failed at line $LINENO"; rollback_ssh; exit 1' ERR

# Harden SSH configuration
update_ssh_config() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}" /etc/ssh/sshd_config; then
    sudo sed -i "s/^${key}.*/${key} ${value}/" /etc/ssh/sshd_config
  else
    echo "${key} ${value}" | sudo tee -a /etc/ssh/sshd_config
  fi
}

echo "Performing SSH configuration..."
update_ssh_config "Port" "$SSH_PORT"
update_ssh_config "PermitRootLogin" "no"
update_ssh_config "PasswordAuthentication" "no"

# Validate SSH config before restart
if ! sudo sshd -t; then
    echo "ERROR: SSH configuration is invalid. Restoring backup..."
    sudo cp "$BACKUP_FILE" /etc/ssh/sshd_config
    exit 1
fi

sudo systemctl restart sshd

# Verify after restart as well
if sudo sshd -t; then
    echo "SSH configuration validated successfully"
else
    echo "WARNING: SSH config validation failed after restart"
fi

# ------------ Firewall configuration

# Harden UFW firewall
echo "Enabling UFW firewall..., do not forget to disable 22 port when $SSH_PORT works"
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow $SSH_PORT/tcp comment "Custom SSH"
sudo ufw allow 22/tcp comment "Default SSH (remove after testing)"
sudo ufw allow 443/tcp comment "HTTPS"
sudo ufw allow 80/tcp comment "HTTP"
sudo ufw --force enable

# UFW status display
echo "Current UFW status:"
sudo ufw status numbered

# Test SSH port availability
echo "Testing SSH connectivity on port $SSH_PORT..."
if timeout 5 nc -z localhost "$SSH_PORT"; then
    echo "SSH port $SSH_PORT is reachable locally"
    if sudo ufw status | grep -q "22/tcp"; then
        sudo ufw delete allow 22/tcp
        echo "Disabled default SSH port 22"
    fi
else
    echo "WARNING: Cannot connect to SSH port $SSH_PORT locally"
    echo "Keeping port 22 open for safety"
fi

# Mark initialization complete
sudo touch /var/log/server-init-complete

echo "Cool, everything is done. You can now test your new SSH port $SSH_PORT."
