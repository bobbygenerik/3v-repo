# Quick Fix Reference - Tres3 Project

## Issues Fixed (October 19, 2025)

### 1. LiveKitManager.kt - Complete Rewrite
**Before:**
```kotlin
class InCallActivity : ComponentActivity() {
    // Duplicate class causing redeclaration error
}
```

**After:**
```kotlin
object LiveKitManager {
    var currentRoom: Room? = null

    suspend fun connectToRoom(context: Context, url: String, token: String) {
        io.livekit.android.LiveKit.loggingLevel = LoggingLevel.DEBUG
        
        val room = LiveKit.create(
            appContext = context.applicationContext,
            overrides = LiveKitOverrides(
                okHttpClient = OkHttpClient.Builder().build()
            )
        )
        
        room.connect(url, token)
        currentRoom = room
    }
    
    fun disconnectFromRoom() {
        CoroutineScope(Dispatchers.Main).launch {
            currentRoom?.disconnect()
            currentRoom = null
        }
    }
}
```

### 2. InCallActivity.kt - Parameter Fix
**Before:**
```kotlin
val trackReferences = rememberParticipantTrackReferences(
    room = room,  // ❌ This parameter doesn't exist
    sources = listOf(io.livekit.android.room.track.Track.Source.CAMERA)
)
```

**After:**
```kotlin
val trackReferences = rememberParticipantTrackReferences(
    sources = listOf(io.livekit.android.room.track.Track.Source.CAMERA)
)
// Room is obtained automatically from RoomLocal.current
```

### 3. Build Configuration
Ensure `app/build.gradle` has proper LiveKit credentials:
```gradle
buildConfigField "String", "LIVEKIT_URL", "\"wss://your-instance.livekit.cloud\""
buildConfigField "String", "LIVEKIT_API_KEY", "\"your-actual-api-key\""
buildConfigField "String", "LIVEKIT_API_SECRET", "\"your-actual-api-secret\""
```

## Build Commands
```bash
# Clean build
./gradlew clean build

# Quick debug build
./gradlew assembleDebug

# Install on device
./gradlew installDebug
```

## Verification Checklist
- [x] Project builds without errors
- [x] No duplicate class declarations
- [x] LiveKitManager properly initialized
- [x] InCallActivity uses correct composable parameters
- [ ] LiveKit API credentials configured (user action required)
- [ ] Tested on device/emulator (user action required)

## Next Steps
1. Update LiveKit credentials in `app/build.gradle`
2. Run `./gradlew assembleDebug`
3. Install and test on a device
4. Verify video call functionality works
