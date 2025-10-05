# local.properties settings for TURN

These keys are read at build time and embedded into BuildConfig for the app to configure ICE servers at runtime. Do not commit secrets.

## Static credentials (your current setup)
```
turn.host=iptvsubz.fun
turn.port=3478
turn.transport=udp
turn.username.mode=STATIC
turn.username=bobbygenerik
turn.password=YOUR_STRONG_PASSWORD

# Optional: force relay to validate your TURN path during testing
turn.forceRelay=true
```

## “Phone-based” username (not compatible with static single-user coturn)
Use only if your coturn accepts the caller’s phone number as a username (not typical for static mode):
```
turn.username.mode=PHONE
turn.password=YOUR_STRONG_PASSWORD
```

## Ephemeral credentials (TURN REST) later
When you switch coturn to use-auth-secret with a shared secret, the app should obtain time-limited username/password from a minimal backend. Then set `turn.username` and `turn.password` at runtime (not from local.properties). I can wire this when you’re ready.
