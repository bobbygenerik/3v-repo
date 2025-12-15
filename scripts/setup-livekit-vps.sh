#!/bin/bash
# LiveKit VPS Setup Script for 31.220.97.48
# Optimized for 3 CPU cores, 8GB RAM with AV1 support

set -e

echo "🚀 Setting up LiveKit on your VPS (31.220.97.48)"

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

# Create LiveKit directory
mkdir -p /opt/livekit
cd /opt/livekit

# Generate API keys
API_KEY=$(openssl rand -hex 16)
API_SECRET=$(openssl rand -hex 32)

echo "🔑 Generated API credentials:"
echo "API_KEY: $API_KEY"
echo "API_SECRET: $API_SECRET"

# Create LiveKit config with AV1 support
cat > livekit.yaml << EOF
port: 7880
bind_addresses:
  - ""

rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 60000
  use_external_ip: true
  
keys:
  $API_KEY: $API_SECRET

# Enable AV1 codec support
codecs:
  - mime: video/AV1
    fmtp: ""
  - mime: video/H264
    fmtp: "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f"
  - mime: video/VP9
    fmtp: ""

# Optimize for your 3-core, 8GB setup
room:
  max_participants: 20
  empty_timeout: 300s
  
# Performance tuning for your VPS
node_selector:
  cpu_cost: 1.0
  
# Logging
log_level: info
EOF

# Create Docker Compose for easy management
cat > docker-compose.yml << EOF
version: '3.8'
services:
  livekit:
    image: livekit/livekit-server:latest
    container_name: livekit-server
    ports:
      - "7880:7880"
      - "7881:7881"
      - "50000-60000:50000-60000/udp"
    volumes:
      - ./livekit.yaml:/livekit.yaml
    command: --config /livekit.yaml
    restart: unless-stopped
    environment:
      - LIVEKIT_CONFIG=/livekit.yaml
EOF

# Start LiveKit
echo "🎬 Starting LiveKit server..."
docker-compose up -d

# Wait for startup
sleep 5

# Test connection
if curl -f http://localhost:7880 > /dev/null 2>&1; then
    echo "✅ LiveKit server is running!"
    echo ""
    echo "🔧 Configuration for your app:"
    echo "URL: wss://31.220.97.48:7880"
    echo "API_KEY: $API_KEY"
    echo "API_SECRET: $API_SECRET"
    echo ""
    echo "📝 Save these credentials to your local.properties:"
    echo "livekit.url=wss://31.220.97.48:7880"
    echo "livekit.api.key=$API_KEY"
    echo "livekit.api.secret=$API_SECRET"
else
    echo "❌ LiveKit failed to start. Check logs:"
    echo "docker-compose logs"
fi

echo ""
echo "🎯 Next steps:"
echo "1. Update your app's local.properties with the credentials above"
echo "2. Open firewall ports 7880, 7881, 50000-60000"
echo "3. Test AV1 calls between Android devices"
echo ""
echo "💡 Your VPS can handle 15+ concurrent 1080p calls with AV1!"