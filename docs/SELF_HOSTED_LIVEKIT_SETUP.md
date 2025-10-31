# Self-Hosted LiveKit Server Setup Guide

## 🎯 Goal
Deploy LiveKit server on your Contabo VPS to save **$8,040/year** vs LiveKit Cloud!

## 📋 Prerequisites

✅ **Contabo VPS 10** (31.220.97.48)
- 3 vCPU, 8 GB RAM, 32 TB bandwidth
- Ubuntu 22.04 or 24.04
- SSH root access

✅ **Domain Setup**
- Create subdomain: `livekit.iptvsubz.fun`
- Point A record to: `31.220.97.48`
- Wait 5-10 minutes for DNS propagation

✅ **Existing Infrastructure**
- Coturn TURN server (already deployed)
- Port 3478 open for TURN

## 🚀 Step-by-Step Deployment

### Step 1: Configure DNS

Add this A record in your DNS provider:

```
Type: A
Name: livekit
Host: livekit.iptvsubz.fun
Value: 31.220.97.48
TTL: 300 (or Auto)
```

**Verify DNS is working:**
```bash
# From your local machine
dig livekit.iptvsubz.fun

# Should return: 31.220.97.48
```

### Step 2: Copy Deployment Script to VPS

```bash
# From your development machine
scp scripts/deploy-livekit-server.sh root@31.220.97.48:/root/

# SSH into VPS
ssh root@31.220.97.48
```

### Step 3: Run Deployment Script

```bash
# On your VPS (as root)
cd /root
chmod +x deploy-livekit-server.sh

# Run the script
./deploy-livekit-server.sh
```

**What it does:**
- ✅ Installs LiveKit server
- ✅ Installs Redis (required by LiveKit)
- ✅ Generates API keys (SAVE THESE!)
- ✅ Obtains SSL certificate (Let's Encrypt)
- ✅ Configures firewall (UFW)
- ✅ Integrates with your coturn TURN server
- ✅ Creates systemd service (auto-start on boot)

**Script will prompt for:**
- TURN server password (for user: bobbygenerik)
- Press Enter to skip if you don't have it yet

### Step 4: Save Your Credentials

The script will output:

```
API Key: abc123def456...
API Secret: xyz789uvw012...

Saved to: /etc/livekit/credentials.txt
```

**IMPORTANT:** Copy these! You'll need them for your apps.

### Step 5: Verify Installation

```bash
# Check LiveKit is running
systemctl status livekit

# Should show: Active: active (running)

# Check logs
journalctl -u livekit -n 50

# Test API endpoint
curl http://31.220.97.48:7880/
```

### Step 6: Update Your Apps

Now update these 3 files with your new credentials:

#### 1. Android App (`local.properties`)
```properties
# Change from:
livekit.url=wss://tres3-l25y6pxz.livekit.cloud
livekit.api.key=APImFx4bcL2KLzy
livekit.api.secret=OQt7AgEfNlaNNf3YpZ504PAxQidFHLtheTfLwSVCoOzD

# To:
livekit.url=wss://livekit.iptvsubz.fun
livekit.api.key=YOUR_NEW_API_KEY
livekit.api.secret=YOUR_NEW_API_SECRET
```

#### 2. Flutter App (`lib/config/environment.dart`)
```dart
class Environment {
  // Change from:
  static const String LIVEKIT_URL = 'wss://tres3-l25y6pxz.livekit.cloud';
  
  // To:
  static const String LIVEKIT_URL = 'wss://livekit.iptvsubz.fun';
}
```

#### 3. Firebase Functions (`functions/.env`)
```bash
# Change from:
LIVEKIT_API_KEY=APImFx4bcL2KLzy
LIVEKIT_API_SECRET=OQt7AgEfNlaNNf3YpZ504PAxQidFHLtheTfLwSVCoOzD
LIVEKIT_URL=wss://tres3-l25y6pxz.livekit.cloud

# To:
LIVEKIT_API_KEY=YOUR_NEW_API_KEY
LIVEKIT_API_SECRET=YOUR_NEW_API_SECRET
LIVEKIT_URL=wss://livekit.iptvsubz.fun
```

### Step 7: Redeploy Firebase Functions

```bash
cd /repos/tres3/3v-repo
firebase deploy --only functions
```

### Step 8: Test Video Calls

1. **Rebuild your app:**
   ```bash
   # Android
   cd /repos/tres3/3v-repo
   ./gradlew clean assembleDebug
   
   # Flutter
   cd tres_flutter
   flutter run
   ```

2. **Make a test call:**
   - Create a room
   - Join with 2 devices
   - Verify video/audio works

3. **Check LiveKit logs:**
   ```bash
   # On VPS
   journalctl -u livekit -f
   
   # Should show connections and room activity
   ```

## 🔧 Maintenance

### View Logs
```bash
# Real-time logs
journalctl -u livekit -f

# Last 100 lines
journalctl -u livekit -n 100

# Logs from last hour
journalctl -u livekit --since "1 hour ago"
```

### Restart Service
```bash
systemctl restart livekit
```

### Check Status
```bash
systemctl status livekit
```

### Update Configuration
```bash
# Edit config
nano /etc/livekit/config.yaml

# Restart to apply
systemctl restart livekit
```

### SSL Certificate Renewal
- Certificates auto-renew via certbot
- Check renewal status: `certbot certificates`
- Manual renewal: `certbot renew`

### Monitor Resources
```bash
# CPU & Memory usage
top

# Disk space
df -h

# Network usage
iftop  # Install: apt install iftop
```

## 🐛 Troubleshooting

### LiveKit won't start
```bash
# Check logs for errors
journalctl -u livekit -n 100

# Common issues:
# - Redis not running: systemctl start redis-server
# - Port 7880 already in use: lsof -i :7880
# - Invalid config: livekit-server --config /etc/livekit/config.yaml
```

### SSL certificate failed
```bash
# Check DNS resolution
dig livekit.iptvsubz.fun

# Check port 80 is open
ufw status | grep 80

# Try again with verbose output
certbot certonly --standalone -d livekit.iptvsubz.fun --dry-run
```

### Can't connect from app
```bash
# Check firewall
ufw status

# Ensure these ports are open:
# - 443 (HTTPS/WSS)
# - 7880 (HTTP API)
# - 50000-60000/udp (WebRTC media)
# - 3478/udp (TURN)

# Test connectivity
curl -v https://livekit.iptvsubz.fun
```

### Performance issues
```bash
# Check system resources
htop  # Install: apt install htop

# Check concurrent connections
ss -tuln | grep 7880

# If too many concurrent calls (>8), consider:
# - Reducing video quality
# - Upgrading VPS bandwidth
```

## 📊 Monitoring

### Check Active Rooms
```bash
# Query LiveKit API
curl -X POST http://31.220.97.48:7880/twirp/livekit.RoomService/ListRooms \
  -H "Authorization: Bearer $(echo -n 'API_KEY:API_SECRET' | base64)" \
  -d '{}'
```

### Resource Usage
```bash
# See LiveKit memory/CPU usage
systemctl status livekit

# Detailed process info
ps aux | grep livekit
```

### Bandwidth Usage
```bash
# Install vnstat for bandwidth monitoring
apt install vnstat
systemctl enable vnstat
systemctl start vnstat

# View bandwidth usage
vnstat -d  # Daily
vnstat -m  # Monthly
```

## 💰 Cost Comparison

| Solution | Monthly Cost | Annual Cost |
|----------|--------------|-------------|
| **LiveKit Cloud** (20 users, 4h/day) | $670 | $8,040 |
| **Self-Hosted** (Contabo VPS) | $7 | $84 |
| **Your Savings** | $663/mo | **$7,956/year** 🎉 |

## 🎯 Capacity Limits

Your Contabo VPS can handle:
- ✅ **20-30 concurrent users** (spread throughout the day)
- ✅ **~8 concurrent HD video calls** (200 Mbit/s port limit)
- ✅ **Unlimited total minutes/month**
- ✅ **32 TB bandwidth** (way more than needed)

## 🔐 Security Best Practices

1. **Keep system updated:**
   ```bash
   apt update && apt upgrade -y
   ```

2. **Enable automatic security updates:**
   ```bash
   apt install unattended-upgrades
   dpkg-reconfigure -plow unattended-upgrades
   ```

3. **Use strong API keys** (already generated randomly)

4. **Monitor logs regularly:**
   ```bash
   journalctl -u livekit --since "24 hours ago" | grep -i error
   ```

5. **Backup configuration:**
   ```bash
   # Backup config and credentials
   tar -czf livekit-backup.tar.gz /etc/livekit/
   ```

## 📞 Support

**Logs location:**
- LiveKit: `journalctl -u livekit`
- Redis: `journalctl -u redis-server`
- Certbot: `/var/log/letsencrypt/`

**Useful resources:**
- LiveKit Docs: https://docs.livekit.io
- Self-hosting guide: https://docs.livekit.io/deploy/
- GitHub issues: https://github.com/livekit/livekit/issues

---

**Ready to save $8,000/year!** 🚀
