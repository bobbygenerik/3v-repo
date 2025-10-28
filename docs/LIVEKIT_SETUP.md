# LiveKit Credentials Setup

## Problem
The Cloud Function is failing with: `Failed to generate tokens: function.config...`

This happens because Firebase Functions v2 uses environment variables instead of `functions.config()`.

## Solution

### Step 1: Get Your LiveKit Credentials

1. Go to your LiveKit server dashboard at: https://livekit.iptvsubz.fun
2. Find your **API Key** and **API Secret**
   - These are usually in Settings > API Keys
   - Or in your LiveKit Cloud dashboard under "API Keys"

### Step 2: Update the .env File

Edit `/workspaces/3v-repo/functions/.env`:

```bash
LIVEKIT_API_KEY=your_actual_api_key_here
LIVEKIT_API_SECRET=your_actual_api_secret_here
```

Replace `your_actual_api_key_here` and `your_actual_api_secret_here` with your real credentials.

### Step 3: Set Environment Variables in Firebase

Run this command to set the environment variables for your deployed Cloud Functions:

```bash
cd /workspaces/3v-repo
firebase functions:secrets:set LIVEKIT_API_KEY
# When prompted, paste your API key

firebase functions:secrets:set LIVEKIT_API_SECRET
# When prompted, paste your API secret
```

**OR** use this one-liner approach:

```bash
# Set both at once
echo "LIVEKIT_API_KEY=your_key_here" | firebase functions:config:set
echo "LIVEKIT_API_SECRET=your_secret_here" | firebase functions:config:set
```

### Step 4: Update the Cloud Function to Use Secrets

The function has been updated to read from environment variables:

```javascript
const apiKey = process.env.LIVEKIT_API_KEY;
const apiSecret = process.env.LIVEKIT_API_SECRET;
```

### Step 5: Redeploy

```bash
cd /workspaces/3v-repo
firebase deploy --only functions:getLiveKitToken
```

## Alternative: Use .env.yaml (Recommended for v2)

Create `/workspaces/3v-repo/functions/.env.yaml`:

```yaml
LIVEKIT_API_KEY: "your_actual_api_key_here"
LIVEKIT_API_SECRET: "your_actual_api_secret_here"
```

Firebase will automatically load these when deploying.

## Verify

After deployment, test a call. Check the logs:

```bash
firebase functions:log --only getLiveKitToken -n 20
```

You should see:
```
LiveKit config - Key exists: true Secret exists: true
SUCCESS: Token generated for user [userId]
```

Instead of:
```
ERROR: LiveKit credentials missing in environment variables
```
