#!/bin/bash

# This script runs on developer side, to initialize a web server.
# It sets up docker, tailscale, a minimal nginx server, and performs basic security hardening.
# - Validates the local .env file first.
# - Uploads the related files to the server.
# - Executes the initialization script on the server.

set -euo pipefail # Exit on error

echo "Cool, let's initialize your new server..."

pwd

#----------- 1. Load and validate environment variables ----------------
if [[ ! -f "./.env" ]]; then
  echo "ERROR: .env file not found."
  exit 1
fi

source .env # load environment variables

# Check existence of required variables
required_vars=(SERVER_HOST INIT_USER INIT_SSH_PORT NEW_USER BACKEND_DOMAIN PROJECT_PATH KEYS_PATH TAILSCALE_AUTH_KEY)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var not set in .env"
    exit 1
  fi
done

# Check files existence

check_file() {
  local file=$1
  if [[ ! -f "$file" ]]; then
    echo "ERROR: Required file $file not found."
    exit 1
  fi
}

check_file "./init_server.sh"
check_file "${KEYS_PATH}/authorized_keys"
check_file "${KEYS_PATH}/origin-key.pem"
check_file "${KEYS_PATH}/origin-cert.pem"
check_file "./project/default.conf"
check_file "./project/docker-compose.yml"

echo "All required variables and files are present."
echo "Server Host: $SERVER_HOST"
echo "Initial User: $INIT_USER"
echo "SSH Port: $INIT_SSH_PORT"

#----------- 2. Upload files to server ----------------
echo "Pushing files to server $SERVER_HOST..."

ssh -p "$INIT_SSH_PORT" "$INIT_USER@$SERVER_HOST" << EOF
    mkdir -p ~/tmp
EOF

# Upload files
scp -P "$INIT_SSH_PORT" ./.env ./init_server.sh "${KEYS_PATH}/authorized_keys" "${KEYS_PATH}/origin-key.pem" "${KEYS_PATH}/origin-cert.pem" ./project/default.conf ./project/docker-compose.yml "$INIT_USER@$SERVER_HOST":~/tmp

#----------- 3. Execute initialization script ----------------
echo "Executing initialization script on server..."

ssh -p "$INIT_SSH_PORT" "$INIT_USER@$SERVER_HOST" << EOF
  chmod +x ~/tmp/init_server.sh
  ~/tmp/init_server.sh
EOF

#----------- 4. Done ----------------
echo "Server initialization completed."
echo "You can now test your SSH connection with the new user and the Tailscale connection."
echo "You can access your backend at https://$BACKEND_DOMAIN if your Cloudflare settings are also correct."
echo ""
echo "Make sure you have verified SSH access via Tailscale."
echo "When everything is confirmed, run ~/tmp/clear.sh via SSH to close the default SSH port(Optional) and clean up."