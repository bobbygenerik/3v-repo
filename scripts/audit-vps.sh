#!/usr/bin/env bash
set -euo pipefail

# Read-only audit for an Ubuntu VPS to check coturn, firewall, and network.
# No changes are made. Outputs a summary.

DOMAIN=${1-}

exe() { echo "+ $*"; "$@"; }

echo "== System =="
exe uname -a || true
exe lsb_release -a || true

echo "\n== Networking =="
exe hostname -I || true
exe ip -4 addr show || true
exe ss -lun | grep -E ':3478|:5349' || true

echo "\n== DNS (optional) =="
if [[ -n "$DOMAIN" ]]; then
  echo "A/AAAA records for $DOMAIN:";
  exe getent ahosts "$DOMAIN" || true
fi

echo "\n== coturn =="
exe systemctl is-enabled coturn || true
exe systemctl is-active coturn || true
exe systemctl status coturn --no-pager || true

if [[ -f /etc/turnserver.conf ]]; then
  echo "\n/etc/turnserver.conf (redacted passwords):"
  # Redact password values
  sed -E 's/(user=.*:).*/\1********/g; s/(static-auth-secret=).*/\1********/g' /etc/turnserver.conf || true
else
  echo "/etc/turnserver.conf not found"
fi

if [[ -f /etc/default/coturn ]]; then
  echo "\n/etc/default/coturn:"; cat /etc/default/coturn || true
fi

echo "\n== Firewall (ufw) =="
if command -v ufw >/dev/null 2>&1; then
  exe ufw status verbose || true
else
  echo "ufw not installed"
fi

echo "\n== Recent logs (coturn) =="
exe journalctl -u coturn -n 200 --no-pager || true

echo "\nAudit complete."
