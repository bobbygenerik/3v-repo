# Remaining Work - Full Feature Implementation

## ❌ Currently Non-Functional

### 1. Contacts System
**Status:** Showing "coming soon" message
**Required:**
- Query Firestore `users` collection
- Filter out current user
- Display in list with avatars
- Implement search filtering
- Add ability to start calls from contacts

### 2. Call History
**Status:** Showing "coming soon" message  
**Required:**
- Query Firestore `calls` collection
- Filter by current user in participants
- Display with timestamps, durations
- Show call direction (incoming/outgoing)
- Link to contact profiles

### 3. Photo Upload
**Status:** Shows "coming soon" toast
**Required:**
- Web file picker integration
- Upload to Firebase Storage (`profile_photos/{uid}`)
- Update user photoURL in Firebase Auth
- Display uploaded photo immediately

### 4. UI Design Mismatch
**Status:** Using old phone container design
**Required:**
- Remove phone container border
- Full-screen layout like Android
- Animated search placeholder (Email → Phone → Display Name)
- Proper toggle buttons (filled vs outline)
- Contact cards matching Android design
- Vertical logo/profile alignment

### 5. Guest Links
**Status:** Service exists but not connected to UI
**Required:**
- Create dialog with guest name input
- Generate link via GuestLinkService
- Share/copy functionality
- Display generated link with warning

## ✅ What's Working

- Video calling (LiveKit integration)
- Firebase authentication
- Profile viewing/editing (except photo)
- Settings screen
- Call screen with all features
- Self-hosted LiveKit server connection

## Priority Order

1. **Contacts** - Most visible missing feature
2. **Call History** - Expected by users
3. **UI Redesign** - Match Android screenshots
4. **Photo Upload** - Profile completion
5. **Guest Links** - Nice to have

## Estimated Work

- Contacts: 30 min
- Call History: 20 min
- Photo Upload: 15 min
- UI Redesign: 45 min
- Guest Links: 20 min

**Total: ~2 hours for full completion**
