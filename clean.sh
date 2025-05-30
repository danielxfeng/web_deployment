#!/bin/bash

set -euo pipefail

source "$HOME/tmp/.env"

echo "WARNING: You can choose, if you want to close the init SSH port."
echo "This is because there are 2 layers of firewalls on Azure or some providers."
echo "Then I can close the port outside, and leave this open for a fallback."

if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    sudo ufw delete allow ${INIT_SSH_PORT}/tcp || true
    echo "INIT_SSH_PORT ${INIT_SSH_PORT} closed."
else
    echo "INIT_SSH_PORT remains open."
fi

echo "Cleaning up temporary files..."
rm -rf ~/tmp
