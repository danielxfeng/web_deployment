#!/bin/bash

# This script runs on the server side, to initialize a web server.
# - Updates the system, installs necessary packages.
# - Installs Docker and docker-compose-plugin.
# - Adds a new user.
# - Copies SSH keys and SSL certificates.
# - Install and configures Tailscale.
# - Configures a firewall with UFW.
# - Disables root login and password authentication for SSH.

set -euo pipefail  # Exit on error

echo "Cool, let's initialize the server..."

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

#----------- Parsing and error handling -----------------
if [[ ! -f "$HOME/tmp/.env" ]]; then
  echo "ERROR: .env file not found."
  exit 1
fi

source "$HOME/tmp/.env"  # Load environment variables

# Check existence of required files

check_file() {
  local file=$1
  if [[ ! -f "$file" ]]; then
    echo "ERROR: Required file $file not found."
    exit 1
  fi
}

check_file "$HOME/tmp/.env"
check_file "$HOME/tmp/authorized_keys"
check_file "$HOME/tmp/origin-key.pem"
check_file "$HOME/tmp/origin-cert.pem"
check_file "$HOME/tmp/default.conf"
check_file "$HOME/tmp/docker-compose.yml"

#----------- Add a new user -----------------
echo "Creating new user: $NEW_USER"

if id "$NEW_USER" &>/dev/null; then
  echo "User $NEW_USER already exists. Skipping user creation."
else
  sudo adduser --disabled-password --gecos "" "$NEW_USER"
  sudo usermod -aG sudo "$NEW_USER"
  sudo usermod -aG docker "$NEW_USER"
  echo "User $NEW_USER created and added to sudo, and docker group."
fi

#----------- Copy SSH keys and SSL certificates -----------------
echo "Copying SSH keys and SSL certificates..."
sudo mkdir -p /etc/ssl/certs
sudo chmod 755 /etc/ssl/certs
sudo cp $HOME/tmp/origin-key.pem /etc/ssl/certs/origin-key.pem
sudo cp $HOME/tmp/origin-cert.pem /etc/ssl/certs/origin-cert.pem
sudo chmod 600 /etc/ssl/certs/origin-key.pem
sudo chmod 644 /etc/ssl/certs/origin-cert.pem
# Copy authorized_keys to the new user's .ssh directory
sudo mkdir -p /home/$NEW_USER/.ssh
sudo cp $HOME/tmp/authorized_keys /home/$NEW_USER/.ssh/authorized_keys
sudo chmod 600 /home/$NEW_USER/.ssh/authorized_keys
sudo chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
# Set permissions for the new user's .ssh directory
sudo chmod 700 /home/$NEW_USER/.ssh
# Set permissions for the new user's home directory
sudo chmod 755 /home/$NEW_USER
# Set ownership for the new user's home directory
sudo chown $NEW_USER:$NEW_USER /home/$NEW_USER

#----------- SSH hardening------------------

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
update_ssh_config "PermitRootLogin" "no"
update_ssh_config "PasswordAuthentication" "no"

# Validate SSH config before restart
if ! sudo sshd -t; then
    echo "ERROR: SSH configuration is invalid."
    exit 1
fi

# Verify after restart as well
if sudo sshd -t; then
  echo "SSH configuration validated successfully, restarting sshd..."
  sudo systemctl restart sshd
else
  echo "ERROR: SSH configuration invalid, aborting."
  exit 1
fi

#----------- Install & start Tailscale ----------------
if ! command -v tailscale &>/dev/null; then
  echo "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
fi

echo "Authenticating Tailscale..."
sudo tailscale up --authkey "$TAILSCALE_AUTH_KEY" --ssh

# ------------ Firewall configuration

# Harden UFW firewall
echo "Enabling UFW firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 41641/udp comment "Tailscale direct UDP"
sudo ufw allow in on lo
sudo ufw allow in on tailscale0
sudo ufw allow ${INIT_SSH_PORT}/tcp comment "SSH on port $INIT_SSH_PORT"
sudo ufw allow 443/tcp comment "HTTPS"
sudo ufw --force enable

# UFW status display
echo "Current UFW status:"
sudo ufw status numbered

#----------- Start Nginx -----------------
echo "Starting Nginx..."
sudo mkdir -p /etc/nginx/conf.d
sudo cp $HOME/tmp/default.conf /etc/nginx/conf.d/default.conf
sudo mkdir -p /home/$NEW_USER/${PROJECT_PATH}
sudo cp $HOME/tmp/docker-compose.yml /home/$NEW_USER/${PROJECT_PATH}/docker-compose.yml
sudo chown $NEW_USER:$NEW_USER /home/$NEW_USER/${PROJECT_PATH}/docker-compose.yml
sudo -u $NEW_USER docker compose -f /home/$NEW_USER/${PROJECT_PATH}/docker-compose.yml up -d

echo "Cool, everything is done. You can now do the testing."
