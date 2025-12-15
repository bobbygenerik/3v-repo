# LiveKit VPS Setup Guide

## Quick Setup on Your VPS (31.220.97.48)

### 1. SSH to Your VPS
```bash
ssh root@31.220.97.48
```

### 2. Run the Setup Script
```bash
# Download setup script
curl -fsSL https://raw.githubusercontent.com/bobbygenerik/3v-repo/main/scripts/setup-livekit-vps.sh -o setup-livekit.sh

# Make executable and run
chmod +x setup-livekit.sh
./setup-livekit.sh
```

### 3. Open Firewall Ports
```bash
# Ubuntu/Debian
ufw allow 7880
ufw allow 7881
ufw allow 50000:60000/udp

# CentOS/RHEL
firewall-cmd --permanent --add-port=7880/tcp
firewall-cmd --permanent --add-port=7881/tcp
firewall-cmd --permanent --add-port=50000-60000/udp
firewall-cmd --reload
```

### 4. Update Your App Configuration

After setup completes, you'll get credentials like:
```
API_KEY: abc123def456...
API_SECRET: xyz789uvw012...
```

Update your `local.properties`:
```properties
livekit.url=ws://31.220.97.48:7880
livekit.api.key=YOUR_GENERATED_API_KEY
livekit.api.secret=YOUR_GENERATED_API_SECRET
```

### 5. Test AV1 Support

Build and test your app. Look for logs:
```
🎯 Preferred Codec: av1
📊 ACTUAL CODEC VERIFICATION:
   🎯 Requested: av1
   ✅ LiveKit Server Accepted: av1
```

## Management Commands

### Check Status
```bash
cd /opt/livekit
docker-compose ps
```

### View Logs
```bash
cd /opt/livekit
docker-compose logs -f
```

### Restart Server
```bash
cd /opt/livekit
docker-compose restart
```

### Stop Server
```bash
cd /opt/livekit
docker-compose down
```

## Expected Performance
- **Concurrent 1080p calls:** 15-20
- **Concurrent 720p calls:** 30+
- **AV1 encoding:** 8-12 calls
- **Memory usage:** ~2-4GB
- **CPU usage:** ~60-80% under load

## Troubleshooting

### Connection Issues
1. Check firewall ports are open
2. Verify Docker is running: `docker ps`
3. Check logs: `docker-compose logs`

### Performance Issues
1. Monitor resources: `htop`
2. Check network: `iftop`
3. Reduce concurrent calls if CPU > 90%

## Security Notes
- API keys are auto-generated and secure
- Server runs on non-standard ports
- Consider adding SSL certificate for production
- Regular backups recommended

Your €5.90/month VPS now provides enterprise-grade video calling with AV1 support!