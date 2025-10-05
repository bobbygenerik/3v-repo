#!/usr/bin/env bash
set -euo pipefail

# Static-credentials coturn deploy script for Ubuntu (run on the VPS as root)
# - Installs coturn
# - Enables the service
# - Backs up existing /etc/turnserver.conf
# - Writes a minimal static-cred config binding to the public IP
# - Optionally configures ufw rules
#
# Usage (on VPS):
#   bash deploy-coturn-static.sh --public-ip 31.220.97.48 --realm iptvsubz.fun --username bobbygenerik [--password 'secret'] [--setup-ufw]

PUBLIC_IP=""
REALM=""
USERNAME=""
PASSWORD=""
SETUP_UFW=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-ip) PUBLIC_IP="$2"; shift 2;;
    --realm) REALM="$2"; shift 2;;
    --username) USERNAME="$2"; shift 2;;
    --password) PASSWORD="$2"; shift 2;;
    --setup-ufw) SETUP_UFW=true; shift;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ $(id -u) -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

if [[ -z "$PUBLIC_IP" || -z "$REALM" || -z "$USERNAME" ]]; then
  echo "Missing required args. Example:" >&2
  echo "  bash $0 --public-ip 31.220.97.48 --realm iptvsubz.fun --username bobbygenerik" >&2
  exit 1
fi

if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "Enter TURN password for user '$USERNAME': " PASSWORD
  echo
fi

echo "== Installing coturn =="
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y coturn

echo "== Enabling service =="
sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn || echo "TURNSERVER_ENABLED=1" > /etc/default/coturn

if [[ -f /etc/turnserver.conf ]]; then
  cp -a /etc/turnserver.conf "/etc/turnserver.conf.bak.$(date +%s)"
fi

cat > /etc/turnserver.conf <<CONF
listening-port=3478
fingerprint
no-tls
no-dtls
listening-ip=$PUBLIC_IP
realm=$REALM
user=$USERNAME:$PASSWORD
lt-cred-mech
no-cli
syslog
simple-log
verbose
# Optional NAT hint if needed:
# external-ip=$PUBLIC_IP
# Relay ports (default range); if you change it, open in firewall accordingly:
# min-port=49152
# max-port=65535
CONF

if $SETUP_UFW && command -v ufw >/dev/null 2>&1; then
  echo "== Configuring ufw =="
  ufw allow 3478/udp || true
  # Note: large ranges can be expensive to manage; leave relay range as-is unless necessary
  # echo "Open relay range as needed: ufw allow 49152:65535/udp"
fi

echo "== Restarting coturn =="
systemctl enable coturn
systemctl restart coturn
sleep 1
systemctl status coturn --no-pager || true

echo "== Listening sockets (expect :3478 on $PUBLIC_IP) =="
ss -lun | grep 3478 || true

echo "Done."
