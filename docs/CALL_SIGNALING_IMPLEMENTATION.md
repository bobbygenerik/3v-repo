# Call Signaling Implementation

## Overview

This document describes the call signaling system that enables peer-to-peer call invitations between users.

## Problem

Previously, when User A initiated a call to User B:
- ✅ User A's device created a LiveKit room
- ✅ User A's InCallActivity launched successfully
- ❌ User B's device received NO notification
- ❌ User B had no way to know a call was happening

## Solution

Implemented a complete call signaling system using Firebase Firestore for real-time notifications.

---

## Architecture

### Components

1. **CallSignalingManager.kt** - Core signaling logic
   - Sends call invitations via Firestore
   - Listens for incoming call invitations
   - Manages invitation lifecycle (pending → ringing → accepted/rejected)

2. **IncomingCallActivity.kt** - Incoming call UI
   - Full-screen caller ID display
   - Accept/Reject buttons
   - Automatic connection on accept

3. **HomeActivity.kt** - Integration point
   - Starts listening for calls on launch
   - Sends invitation when initiating call
   - Stops listening when destroyed

---

## Call Flow

### Outgoing Call (User A → User B)

```
1. User A clicks call button
   ↓
2. HomeActivity.initiateCall(contact)
   ↓
3. Request camera/microphone permissions
   ↓
4. Create LiveKit room with User A's token
   ↓
5. Get separate token for User B
   ↓
6. CallSignalingManager.sendCallInvitation()
   - Write to: users/{User B}/callSignals
   - Data: { type, fromUserId, fromUserName, roomName, url, token, status: "pending" }
   ↓
7. Launch InCallActivity for User A
```

### Incoming Call (User B receives)

```
1. CallSignalingManager is listening in HomeActivity
   ↓
2. Firestore snapshot listener detects new callSignal
   ↓
3. Mark invitation status as "ringing"
   ↓
4. Launch IncomingCallActivity with invitation data
   ↓
5. User B sees full-screen incoming call UI
   ↓
6a. User B clicks Accept:
    - Mark invitation as "accepted"
    - Connect to room with provided token
    - Launch InCallActivity
    
6b. User B clicks Reject:
    - Mark invitation as "rejected"
    - Close IncomingCallActivity
```

---

## Firestore Structure

### Call Signals Collection

```
users/{userId}/callSignals/{invitationId}
{
  type: "call_invite",
  fromUserId: "abc123",
  fromUserName: "John Doe",
  roomName: "room-xyz",
  url: "wss://livekit.example.com",
  token: "eyJhbG...",
  timestamp: Timestamp,
  status: "pending" | "ringing" | "accepted" | "rejected" | "missed"
}
```

### Status Lifecycle

- **pending**: Just created, not yet seen by recipient
- **ringing**: Recipient's device detected it, showing UI
- **accepted**: Recipient accepted, joining call
- **rejected**: Recipient declined
- **missed**: Recipient didn't respond (future feature)

---

## Security Rules

Required Firestore security rules:

```javascript
match /users/{userId}/callSignals/{signalId} {
  // Anyone can write (to send invitations)
  allow create: if request.auth != null;
  
  // Only the owner can read their signals
  allow read: if request.auth.uid == userId;
  
  // Only the owner can update their signals (to mark as accepted/rejected)
  allow update: if request.auth.uid == userId;
  
  // Only the owner can delete old signals
  allow delete: if request.auth.uid == userId;
}
```

---

## Key Features

### Real-time Notifications
- Uses Firestore snapshot listeners for instant delivery
- No polling required
- Works when app is in foreground

### Lifecycle Management
- Listener starts in `HomeActivity.onCreate()`
- Listener stops in `HomeActivity.onDestroy()`
- Prevents memory leaks

### Status Tracking
- Tracks invitation state for analytics
- Can show "missed call" history (future)
- Enables call history features

### Error Handling
- Graceful fallback if invitation send fails
- Logs all signaling events for debugging
- Continues call setup even if notification fails

---

## Testing

### Two-Device Test

1. **Setup**: Install app on Device A and Device B
2. **Sign In**: User A on Device A, User B on Device B
3. **Test Call**: User A calls User B
4. **Expected Result**: 
   - Device A launches InCallActivity immediately
   - Device B shows IncomingCallActivity with User A's name
   - User B can accept or reject
   - On accept, both users see each other in video call

### Logs to Monitor

```
Device A (Caller):
  📤 Sending call invitation to [Name]
  ✅ Call invitation sent successfully

Device B (Callee):
  🎧 Starting to listen for call invitations
  📞 Incoming call from: [Name]
  ✅ Call invitation accepted
```

---

## Future Enhancements

### Push Notifications (FCM)
- Currently requires app to be open
- Future: Use Firebase Cloud Messaging for background calls
- Would trigger push notification when app is closed

### Call Timeout
- Auto-mark as "missed" after 30 seconds
- Show notification for missed calls

### Multi-Device Support
- Handle case where user is signed in on multiple devices
- Let user answer from any device

### Group Call Invitations
- Extend to support adding multiple participants
- Already partially implemented in InCallActivity's AddPersonDialog

---

## Troubleshooting

### User doesn't receive call invitation

**Check:**
1. Is HomeActivity running? (Listener only active when app open)
2. Are Firestore rules correct?
3. Check logcat for "📞 Incoming call" message
4. Verify user IDs are correct in Firestore

**Debug:**
```bash
# Check Firestore directly
adb logcat | grep "CallSignaling"
```

### Call invitation sent but not showing

**Possible causes:**
1. App was in background (listener not active)
2. Firestore permissions issue
3. Snapshot listener crashed

**Solution:**
- Ensure app is in foreground on recipient device
- Check logcat for Firestore errors
- Verify "status" field is "pending"

---

## Files Modified/Created

### New Files
- `app/src/main/java/com/example/tres3/CallSignalingManager.kt`
- `app/src/main/java/com/example/tres3/IncomingCallActivity.kt`

### Modified Files
- `app/src/main/java/com/example/tres3/HomeActivity.kt`
  - Added listener in `onCreate()`
  - Added invitation sending in `initiateCallAfterPermissions()`
  - Added `onDestroy()` to clean up listener

- `app/src/main/AndroidManifest.xml`
  - Registered `IncomingCallActivity`
  - Added `showWhenLocked` and `turnScreenOn` attributes

---

## Related to Battery Optimization Fix

This call signaling system works together with the battery optimization changes:

1. **Foreground Service**: Keeps app alive during active call
2. **Battery Exemption**: Prevents system from freezing app
3. **Call Signaling**: Enables users to connect in the first place

All three systems are required for reliable video calling.
