#!/bin/bash

# This script is to initialize a web server.
# - It installs Docker and docker-compose-plugin.
# - It sets up SSH with a custom port and adds a public key for CI/CD.
# - It configures a firewall with UFW.
# - It disables root login and password authentication for SSH.

set -euo pipefail # Exit on error

source .env # Load environment variables

echo "Cool, let's initialize the server..."

echo "The system is updating, if restarted, please run this script again."
sudo apt update && sudo apt upgrade -y

if ! command -v docker &> /dev/null
then
  echo "Docker not found. Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
else
  echo "Docker already installed, skipping."
fi

if ! dpkg -s docker-compose-plugin &> /dev/null
then
  echo "docker-compose-plugin not found. Installing..."
  sudo apt install -y docker-compose-plugin
else
  echo "docker-compose-plugin already installed, skipping."
fi

mkdir -p ~/.ssh
chmod 700 ~/.ssh
if ! grep -q "$CICD_PUB_KEY" ~/.ssh/authorized_keys; then
    echo "CI/CD public key not found in authorized_keys, adding it..."
    echo "$CICD_PUB_KEY" >> ~/.ssh/authorized_keys
else
    echo "CI/CD public key already exists in authorized_keys, skipping."
fi
chmod 600 ~/.ssh/authorized_keys


echo "Performing SSH configuration..."
sudo sed -i '/^#Port /d' /etc/ssh/sshd_config
sudo sed -i '/^Port /d' /etc/ssh/sshd_config
echo "Port $SSH_PORT" | sudo tee -a /etc/ssh/sshd_config
sudo sed -i '/^#PasswordAuthentication /d' /etc/ssh/sshd_config
sudo sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config
sudo sed -i '/^#PermitRootLogin /d' /etc/ssh/sshd_config
sudo sed -i '/^PermitRootLogin /d' /etc/ssh/sshd_config
echo "PermitRootLogin no" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd


echo "enabling ufw firewall..., do not forget to disable 22 port when $SSH_PORT works"
sudo ufw allow $SSH_PORT
sudo ufw allow 22 # Disable it when $SSH_PORT works
sudo ufw allow 443
sudo ufw enable


echo "Cool, everything is done, you can now test your new SSH port $SSH_PORT."
