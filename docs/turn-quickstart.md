# TURN (coturn) quickstart for your VPS

This guide helps you bring up a TURN server (coturn) on Ubuntu with static credentials first, and shows how to switch to ephemeral credentials later.

## Option A: Static credentials (simplest)

- Good for personal/testing use. You’ll create a fixed username/password that the app uses.
- Steps below assume Ubuntu 22.04+/24.04.

### 1) Install coturn
```
sudo apt update
sudo apt install -y coturn
```

### 2) Enable coturn as a service
```
echo "TURNSERVER_ENABLED=1" | sudo tee /etc/default/coturn
```

### 3) Create /etc/turnserver.conf

Replace YOUR_PUBLIC_IP, YOUR_REALM (e.g., yourdomain.com), USERNAME, and STRONG_PASSWORD.
```
listening-port=3478
fingerprint
no-tls
no-dtls
listening-ip=YOUR_PUBLIC_IP
realm=YOUR_REALM
user=USERNAME:STRONG_PASSWORD
lt-cred-mech
no-cli
simple-log
verbose
# Relay ports (default range); open in firewall if needed
# min-port=49152
# max-port=65535

; Optional NAT hint if your VPS has private/internal IP
; external-ip=PUBLIC_IP/INTERNAL_IP
```

- Notes:
  - `lt-cred-mech` enables long-term (static) credentials.
  - If you have a domain and want TLS later, you can add a cert and use `tls-listening-port=5349` and `cert`/`pkey` settings.

### 4) Open firewall
If you use ufw:
```
sudo ufw allow 3478/udp
sudo ufw allow 49152:65535/udp
```

### 5) Start and enable coturn
```
sudo systemctl enable coturn
sudo systemctl restart coturn
sudo systemctl status coturn --no-pager

Also ensure your DNS A record for your domain points to the VPS public IP. Using the domain in `realm` helps auth and TLS later.
```

### 6) Fill in the app’s local.properties
On your development machine (not committed):
```
turn.host=YOUR_PUBLIC_IP
turn.port=3478
turn.transport=udp
turn.username.mode=STATIC
turn.username=USERNAME
turn.password=STRONG_PASSWORD
```

That’s it. The app will relay through your server when needed.

Optional test: force relay usage from the app (useful to confirm it’s working)
```
turn.forceRelay=true
```
Remember to turn this back off; normally WebRTC prefers direct P2P and uses TURN only when necessary.

## Option B: Ephemeral credentials (TURN REST)

- More secure for public distribution. Instead of sharing a fixed password, clients obtain short-lived credentials generated with a shared secret.
- Coturn settings (replace YOUR_PUBLIC_IP, YOUR_REALM, and YOUR_SHARED_SECRET):
```
listening-port=3478
fingerprint
no-tls
no-dtls
listening-ip=YOUR_PUBLIC_IP
realm=YOUR_REALM
use-auth-secret
static-auth-secret=YOUR_SHARED_SECRET
no-cli
simple-log
verbose
```
- You’d then generate credentials (username includes a timestamp; password is HMAC over that using the shared secret). This is typically done in a tiny backend. If you want a client-only demo, I can include a quick generator for dev builds, but don’t ship that to production.

### App configuration (ephemeral)
In local.properties you’d set:
```
turn.host=YOUR_PUBLIC_IP
turn.port=3478
turn.transport=udp
# Username is generated at runtime; leave static username blank.
turn.username.mode=STATIC
turn.username=
turn.password=
```
And add logic (backend recommended) to return the generated username/password; I can wire this into the app when you’re ready.

## TLS (optional, stricter networks)
- To support TLS on 5349, add a cert to your VPS and update coturn:
```
tls-listening-port=5349
no-udp
cert=/etc/letsencrypt/live/yourdomain.com/fullchain.pem
pkey=/etc/letsencrypt/live/yourdomain.com/privkey.pem
```
- Then set `turn.transport=tls` in local.properties. (The app will use `turns:` and TCP under the hood.)

## Verify
- Logs: `sudo journalctl -u coturn -n 200 --no-pager`
- Port check: `sudo ss -lun | grep 3478`
- If calls still connect directly, that’s okay—TURN only relays when P2P fails.

## Troubleshooting tips
- Make sure your VPS provider allows UDP and high ports.
- If behind NAT, set `external-ip=PUBLIC_IP/INTERNAL_IP` in coturn.
- Open the relay port range if you customize min/max ports.

## Reset or wipe

If you want to start over with coturn only (recommended):

1) Copy the reset script to your VPS and run it as root:
```
scp scripts/reset-coturn.sh user@your-vps:/tmp/
ssh user@your-vps 'sudo bash /tmp/reset-coturn.sh'
```
2) Recreate `/etc/turnserver.conf` using the config above and start the service again.

If you mean fully wiping the entire VPS: that can only be done from your VPS provider’s dashboard (rebuild/reimage). Doing that here isn’t possible and will erase everything on that VM. Only do it if you truly want a clean slate.

---
If you want, I can generate a tailored coturn.conf file with your IP and a strong password and include a one-liner to deploy it.
