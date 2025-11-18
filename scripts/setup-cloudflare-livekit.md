# Cloudflare Setup for LiveKit

## Step 1: Enable Proxy (Orange Cloud)
1. Go to https://dash.cloudflare.com/
2. Select domain: `iptvsubz.fun`
3. Click "DNS" in sidebar
4. Find `livekit.iptvsubz.fun` record
5. Click gray cloud ☁️ to turn it orange 🟠 (Proxied)

## Step 2: Configure SSL/TLS Settings
1. In Cloudflare dashboard, go to "SSL/TLS" section
2. Set SSL/TLS encryption mode to: **Full** (not Full Strict)
   - This allows Cloudflare to connect to your server on port 7880 without SSL

## Step 3: Enable WebSocket Support
1. Go to "Network" section
2. Scroll down to "WebSockets"
3. Make sure it's **enabled** (toggle ON)

## Step 4: Add Origin Rules (Important for LiveKit)
1. Go to "Rules" → "Origin Rules"
2. Click "Create rule"
3. Name: `LiveKit Port Forward`
4. When incoming requests match: 
   - Custom filter: `http.host eq "livekit.iptvsubz.fun"`
5. Then:
   - Destination Port: Override to `7880`
6. Click "Deploy"

## Step 5: Test Connection
After 2-3 minutes, test:
```bash
curl https://livekit.iptvsubz.fun
```

Should return LiveKit response (not connection refused).

## Alternative: If Cloudflare doesn't work

Use an nginx reverse proxy on your VPS:
```bash
ssh root@31.220.97.48
apt install nginx certbot python3-certbot-nginx -y

cat > /etc/nginx/sites-available/livekit << 'EOF'
server {
    listen 443 ssl http2;
    server_name livekit.iptvsubz.fun;

    ssl_certificate /etc/letsencrypt/live/livekit.iptvsubz.fun/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/livekit.iptvsubz.fun/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:7880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
}
EOF

ln -s /etc/nginx/sites-available/livekit /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

Then turn Cloudflare proxy OFF (gray cloud) and test directly.
