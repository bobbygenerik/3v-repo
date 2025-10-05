#!/usr/bin/env bash
set -euo pipefail

# This script resets coturn on an Ubuntu server.
# It stops the service, disables it, purges packages, removes config files,
# and optionally cleans ufw rules related to TURN.
#
# Usage on the VPS:
#   bash reset-coturn.sh [--purge-ufw]

if [[ $(id -u) -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

systemctl stop coturn || true
systemctl disable coturn || true

# Remove package and dependencies
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get purge -y coturn || true
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

# Remove config
rm -f /etc/default/coturn || true
rm -f /etc/turnserver.conf || true
rm -rf /var/lib/turn || true

# Optional: UFW cleanup for common rules
if [[ ${1-} == "--purge-ufw" ]]; then
  if command -v ufw >/dev/null 2>&1; then
    ufw --force delete allow 3478/udp || true
    # Relay range if previously opened
    for p in $(seq 49152 65535); do :; done # placeholder
    # Note: UFW doesn't support deleting ranges by default; skip to avoid long loops
    echo "If you opened a relay range, review: sudo ufw status numbered"
  fi
fi

echo "coturn reset complete."
