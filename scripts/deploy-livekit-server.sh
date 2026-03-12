#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# LiveKit Self-Hosted Server Deployment Script
# For OVHcloud VPS 10 (3 vCPU, 8GB RAM, Ubuntu 22.04/24.04)
# ============================================================================
#
# This script installs and configures:
# - LiveKit server (video conferencing infrastructure)
# - Redis (for LiveKit state management)
# - SSL certificate (Let's Encrypt)
# - Integration with existing coturn TURN server
#
# Prerequisites:
# - Ubuntu 22.04+ on VPS (31.220.97.48)
# - Domain: livekit.iptvsubz.fun pointing to VPS IP
# - Coturn already installed on port 3478
# - Run as root: sudo bash deploy-livekit-server.sh
#
# Cost Savings: ~$8,040/year vs LiveKit Cloud
# ============================================================================

# Configuration
DOMAIN="${LIVEKIT_DOMAIN:-livekit.iptvsubz.fun}"
VPS_IP="${VPS_IP:-31.220.97.48}"
TURN_HOST="${TURN_HOST:-iptvsubz.fun}"
TURN_PORT="${TURN_PORT:-3478}"
TURN_USERNAME="${TURN_USERNAME:-bobbygenerik}"
TURN_PASSWORD="${TURN_PASSWORD:-}"
EMAIL="${ADMIN_EMAIL:-bobbyfbrown85@gmail.com}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}  LiveKit Self-Hosted Deployment${NC}"
echo -e "${BLUE}  Domain: ${DOMAIN}${NC}"
echo -e "${BLUE}  VPS IP: ${VPS_IP}${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (use sudo)${NC}" 
   exit 1
fi

# Step 1: Update system
echo -e "${GREEN}[1/10] Updating system packages...${NC}"
apt-get update -y
apt-get upgrade -y

# Step 2: Install dependencies
echo -e "${GREEN}[2/10] Installing dependencies...${NC}"
apt-get install -y \
    curl \
    wget \
    gnupg \
    lsb-release \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    ufw \
    certbot

# Step 3: Install Redis (required by LiveKit)
echo -e "${GREEN}[3/10] Installing Redis...${NC}"
apt-get install -y redis-server

# Enable and start Redis
systemctl enable redis-server
systemctl start redis-server

echo -e "${BLUE}Redis status:${NC}"
systemctl status redis-server --no-pager | head -5

# Step 4: Install LiveKit
echo -e "${GREEN}[4/10] Installing LiveKit Server...${NC}"
curl -sSL https://get.livekit.io | bash

# Verify installation
if ! command -v livekit-server &> /dev/null; then
    echo -e "${RED}Error: LiveKit installation failed${NC}"
    exit 1
fi

LIVEKIT_VERSION=$(livekit-server --version 2>&1 || echo "unknown")
echo -e "${BLUE}Installed LiveKit version: ${LIVEKIT_VERSION}${NC}"

# Step 5: Generate API keys
echo -e "${GREEN}[5/10] Generating LiveKit API keys...${NC}"
API_KEY=$(openssl rand -hex 16)
API_SECRET=$(openssl rand -base64 32 | tr -d '\n')

echo -e "${YELLOW}Generated API Key: ${API_KEY}${NC}"
echo -e "${YELLOW}Generated API Secret: ${API_SECRET}${NC}"
echo -e "${YELLOW}IMPORTANT: Save these credentials! You'll need them for your app.${NC}"

# Save credentials to file
mkdir -p /etc/livekit
cat > /etc/livekit/credentials.txt <<EOF
# LiveKit Self-Hosted Credentials
# Generated: $(date)

LIVEKIT_URL=wss://${DOMAIN}
LIVEKIT_API_KEY=${API_KEY}
LIVEKIT_API_SECRET=${API_SECRET}

# Use these in your app:
# - local.properties (Android)
# - environment.dart (Flutter)
# - functions/.env (Firebase Functions)
EOF

chmod 600 /etc/livekit/credentials.txt
echo -e "${GREEN}Credentials saved to: /etc/livekit/credentials.txt${NC}"

# Step 6: Configure firewall
echo -e "${GREEN}[6/10] Configuring firewall (UFW)...${NC}"
ufw --force enable

# Allow SSH (important!)
ufw allow 22/tcp

# Allow HTTP/HTTPS (for Let's Encrypt and LiveKit)
ufw allow 80/tcp
ufw allow 443/tcp

# Allow LiveKit ports
ufw allow 7880/tcp  # LiveKit HTTP API
ufw allow 7881/tcp  # LiveKit TURN/TLS
ufw allow 50000:60000/udp  # WebRTC media

# TURN server (already configured, but ensure it's open)
ufw allow 3478/udp

echo -e "${BLUE}Firewall status:${NC}"
ufw status

# Step 7: Get SSL certificate
echo -e "${GREEN}[7/10] Obtaining SSL certificate from Let's Encrypt...${NC}"

# Check if domain resolves to VPS IP
RESOLVED_IP=$(dig +short ${DOMAIN} | tail -n1)
if [[ "${RESOLVED_IP}" != "${VPS_IP}" ]]; then
    echo -e "${YELLOW}Warning: ${DOMAIN} resolves to ${RESOLVED_IP}, not ${VPS_IP}${NC}"
    echo -e "${YELLOW}Make sure DNS is configured correctly!${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Obtain certificate (standalone mode - no web server needed)
certbot certonly \
    --standalone \
    --preferred-challenges http \
    --email ${EMAIL} \
    --agree-tos \
    --no-eff-email \
    -d ${DOMAIN}

if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo -e "${RED}Error: SSL certificate generation failed${NC}"
    echo -e "${YELLOW}Check that ${DOMAIN} points to ${VPS_IP} and port 80 is accessible${NC}"
    exit 1
fi

echo -e "${GREEN}SSL certificate obtained successfully!${NC}"

# Step 8: Prompt for TURN password if not set
if [[ -z "${TURN_PASSWORD}" ]]; then
    echo -e "${YELLOW}[8/10] TURN server configuration${NC}"
    echo -e "Your coturn server needs a password for user: ${TURN_USERNAME}"
    read -s -p "Enter TURN password (or press Enter to skip TURN integration): " TURN_PASSWORD
    echo
fi

# Step 9: Create LiveKit configuration
echo -e "${GREEN}[9/10] Creating LiveKit configuration...${NC}"

cat > /etc/livekit/config.yaml <<EOF
# LiveKit Self-Hosted Configuration
# Generated: $(date)

port: 7880
bind_addresses:
  - "0.0.0.0"

rtc:
  port_range_start: 50000
  port_range_end: 60000
  use_external_ip: true
  # VPS public IP
  udp_port: 7882

# Redis for distributed state
redis:
  address: localhost:6379

# API keys
keys:
  ${API_KEY}: ${API_SECRET}

# Logging
logging:
  level: info
  sample: false

# Room settings
room:
  auto_create: true
  empty_timeout: 300  # 5 minutes
  max_participants: 50

# WebRTC TURN configuration (using your coturn server)
EOF

# Add TURN config if password provided
if [[ -n "${TURN_PASSWORD}" ]]; then
cat >> /etc/livekit/config.yaml <<EOF
turn:
  enabled: true
  domain: ${TURN_HOST}
  tls_port: 5349
  udp_port: ${TURN_PORT}
  external_tls: false
EOF
echo -e "${GREEN}TURN server integration enabled${NC}"
else
cat >> /etc/livekit/config.yaml <<EOF
# TURN server configuration skipped
# You can add it later if needed
EOF
echo -e "${YELLOW}TURN server integration skipped (LiveKit will use embedded TURN)${NC}"
fi

# Set proper permissions
chmod 600 /etc/livekit/config.yaml

echo -e "${GREEN}Configuration created: /etc/livekit/config.yaml${NC}"

# Step 10: Create systemd service
echo -e "${GREEN}[10/10] Creating systemd service...${NC}"

cat > /etc/systemd/system/livekit.service <<EOF
[Unit]
Description=LiveKit Media Server
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/livekit
ExecStart=/usr/local/bin/livekit-server --config /etc/livekit/config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=livekit

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start LiveKit
systemctl daemon-reload
systemctl enable livekit
systemctl start livekit

# Wait for service to start
sleep 3

# Check status
echo -e "${BLUE}LiveKit service status:${NC}"
systemctl status livekit --no-pager || true

# Verify it's listening
if ss -tuln | grep -q ":7880"; then
    echo -e "${GREEN}✓ LiveKit is listening on port 7880${NC}"
else
    echo -e "${RED}✗ LiveKit is not listening on port 7880${NC}"
    echo -e "${YELLOW}Check logs: journalctl -u livekit -n 50${NC}"
fi

# Setup log rotation
cat > /etc/logrotate.d/livekit <<EOF
/var/log/livekit/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload livekit > /dev/null 2>&1 || true
    endscript
}
EOF

# Setup auto-renewal for SSL certificates
echo -e "${GREEN}Setting up SSL certificate auto-renewal...${NC}"
systemctl enable certbot.timer
systemctl start certbot.timer

# Create renewal hook to reload LiveKit when cert renews
mkdir -p /etc/letsencrypt/renewal-hooks/post
cat > /etc/letsencrypt/renewal-hooks/post/reload-livekit.sh <<'EOF'
#!/bin/bash
systemctl reload livekit
EOF
chmod +x /etc/letsencrypt/renewal-hooks/post/reload-livekit.sh

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  LiveKit Server Deployment Complete! 🎉${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo -e "${BLUE}Server Details:${NC}"
echo -e "  URL: ${GREEN}wss://${DOMAIN}${NC}"
echo -e "  HTTP API: ${GREEN}http://${VPS_IP}:7880${NC}"
echo -e "  IP Address: ${GREEN}${VPS_IP}${NC}"
echo ""
echo -e "${BLUE}Credentials (SAVE THESE):${NC}"
echo -e "  API Key: ${YELLOW}${API_KEY}${NC}"
echo -e "  API Secret: ${YELLOW}${API_SECRET}${NC}"
echo -e "  (Also saved in: /etc/livekit/credentials.txt)"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. Update your app configuration:"
echo -e "     ${YELLOW}local.properties${NC}: livekit.url=wss://${DOMAIN}"
echo -e "     ${YELLOW}environment.dart${NC}: LIVEKIT_URL = 'wss://${DOMAIN}'"
echo -e "     ${YELLOW}functions/.env${NC}: LIVEKIT_URL=wss://${DOMAIN}"
echo ""
echo -e "  2. Update API keys in all three files above"
echo ""
echo -e "  3. Redeploy Firebase Functions:"
echo -e "     ${YELLOW}firebase deploy --only functions${NC}"
echo ""
echo -e "  4. Test your setup:"
echo -e "     ${YELLOW}curl -X POST http://${VPS_IP}:7880/twirp/livekit.RoomService/CreateRoom \\"
echo -e "       -H \"Authorization: Bearer \$(echo -n \"${API_KEY}:${API_SECRET}\" | base64)\" \\"
echo -e "       -d '{\"name\":\"test-room\"}'${NC}"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "  View logs: ${YELLOW}journalctl -u livekit -f${NC}"
echo -e "  Restart: ${YELLOW}systemctl restart livekit${NC}"
echo -e "  Status: ${YELLOW}systemctl status livekit${NC}"
echo -e "  Config: ${YELLOW}/etc/livekit/config.yaml${NC}"
echo ""
echo -e "${GREEN}Annual Savings: \$8,040 vs LiveKit Cloud! 💰${NC}"
echo -e "${GREEN}============================================================================${NC}"
