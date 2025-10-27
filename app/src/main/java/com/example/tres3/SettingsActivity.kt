package com.example.tres3

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tres3.video.VideoCodecManager

class SettingsActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            SettingsScreen()
        }
    }
}

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val sharedPrefs = remember { context.getSharedPreferences("settings", Context.MODE_PRIVATE) }

    // State for settings
    var notificationsEnabled by remember { mutableStateOf(sharedPrefs.getBoolean("notifications", true)) }
    var headsUpNotifications by remember { mutableStateOf(sharedPrefs.getBoolean("heads_up_notifications", false)) }
    var callQuality by remember { mutableStateOf(sharedPrefs.getString("call_quality", "Auto") ?: "Auto") }
    var voiceIsolation by remember { mutableStateOf(sharedPrefs.getBoolean("voice_isolation", true)) }
    var boostUltraOnCharger by remember { mutableStateOf(sharedPrefs.getBoolean("boost_ultra_on_charger", false)) }
    var blurIntensity by remember { mutableStateOf(FeatureFlags.getBackgroundBlurIntensity()) }
    var developerMode by remember { mutableStateOf(FeatureFlags.isDeveloperModeEnabled()) }
    var perfOverlay by remember { mutableStateOf(FeatureFlags.isPerformanceOverlayEnabled()) }
    
    // Advanced codec settings
    val advancedCodecsEnabled = remember { FeatureFlags.isAdvancedCodecsEnabled() }
    var selectedCodec by remember { 
        mutableStateOf(
            if (advancedCodecsEnabled) {
                VideoCodecManager.loadPreferredCodec(context).displayName
            } else {
                "H.264 (AVC)"
            }
        )
    }
    
    // Get available codecs for this device
    val availableCodecs = remember { 
        if (advancedCodecsEnabled) {
            VideoCodecManager.getAvailableCodecs(context).map { it.displayName }
        } else {
            listOf("H.264 (AVC)")
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.BackgroundDark)
            .windowInsetsPadding(WindowInsets.systemBars)
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Text(
            text = "Settings",
            color = AppColors.TextLight,
            fontSize = 24.sp,
            modifier = Modifier.padding(bottom = 24.dp)
        )

        // Notifications Toggle
        SettingsSwitch(
            title = "Notifications",
            subtitle = "Receive call notifications",
            checked = notificationsEnabled,
            onCheckedChange = { newValue ->
                notificationsEnabled = newValue
                sharedPrefs.edit().putBoolean("notifications", newValue).apply()
            }
        )

        Spacer(modifier = Modifier.height(16.dp))
        
        // Heads-up Notifications Toggle
        SettingsSwitch(
            title = "Minimal Notifications",
            subtitle = "Show drop-down notification instead of full-screen (default: full-screen)",
            checked = headsUpNotifications,
            onCheckedChange = { newValue ->
                headsUpNotifications = newValue
                sharedPrefs.edit().putBoolean("heads_up_notifications", newValue).apply()
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Voice Isolation (mic processing)
        SettingsSwitch(
            title = "Voice Isolation",
            subtitle = "Reduce background noise (NS/AGC on)",
            checked = voiceIsolation,
            onCheckedChange = { newValue ->
                voiceIsolation = newValue
                sharedPrefs.edit().putBoolean("voice_isolation", newValue).apply()
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Prefer 60 fps automatically (Auto boost)
        SettingsSwitch(
            title = "Auto boost to 60 fps",
            subtitle = "Use Ultra (1080p/60) when thermals are OK on capable devices",
            checked = boostUltraOnCharger,
            onCheckedChange = { newValue ->
                boostUltraOnCharger = newValue
                sharedPrefs.edit().putBoolean("boost_ultra_on_charger", newValue).apply()
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Portrait blur intensity
        Text(text = "Portrait Blur Intensity", color = AppColors.TextLight, fontSize = 16.sp)
        Spacer(modifier = Modifier.height(6.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(AppColors.Gray.copy(alpha = 0.1f))
                .padding(horizontal = 16.dp, vertical = 10.dp)
        ) {
            Slider(
                value = blurIntensity / 100f,
                onValueChange = { v -> blurIntensity = (v * 100).toInt().coerceIn(0, 100) },
                onValueChangeFinished = { FeatureFlags.setBackgroundBlurIntensity(blurIntensity) }
            )
            Text(
                text = "${blurIntensity}",
                color = AppColors.PrimaryBlue,
                fontSize = 14.sp
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Developer section
        Text(text = "Developer", color = AppColors.TextLight, fontSize = 16.sp)
        Spacer(modifier = Modifier.height(6.dp))
        SettingsSwitch(
            title = "Developer Mode",
            subtitle = "Enable advanced options and logs",
            checked = developerMode,
            onCheckedChange = { newValue ->
                developerMode = newValue
                FeatureFlags.setDeveloperModeEnabled(newValue)
            }
        )
        Spacer(modifier = Modifier.height(12.dp))
        SettingsSwitch(
            title = "Call Health Overlay",
            subtitle = "Show call health: quality, codec, mic/audio",
            checked = perfOverlay,
            onCheckedChange = { newValue ->
                perfOverlay = newValue
                // Stored under developer_mode scope in FeatureFlags; mimic via SharedPreferences key
                context.getSharedPreferences("feature_flags", Context.MODE_PRIVATE)
                    .edit().putBoolean("show_performance_overlay", newValue).apply()
            }
        )

        // Call Quality Dropdown
        SettingsDropdown(
            title = "Call Quality",
            subtitle = "Select video quality",
            selectedValue = callQuality,
            options = listOf("Low", "Auto", "High", "Ultra"),
            onValueChange = { newValue ->
                callQuality = newValue
                sharedPrefs.edit().putString("call_quality", newValue).apply()
            }
        )
        
        // Advanced Codec Selection (only if feature flag enabled)
        if (advancedCodecsEnabled && availableCodecs.size > 1) {
            Spacer(modifier = Modifier.height(16.dp))
            
            // Reorder codecs to priority: H.265, VP9, H.264, VP8
            val priorityOrder = listOf("H.265 (HEVC)", "VP9", "H.264 (AVC)", "VP8")
            val sortedCodecs = availableCodecs.sortedBy { codec ->
                priorityOrder.indexOf(codec).let { if (it == -1) Int.MAX_VALUE else it }
            }
            
            SettingsDropdown(
                title = "Video Codec (Priority Order)",
                subtitle = "H.265 > VP9 > H.264 > VP8 (${sortedCodecs.size} available)",
                selectedValue = selectedCodec,
                options = sortedCodecs,
                onValueChange = { newValue ->
                    selectedCodec = newValue
                    // Find the codec enum by display name
                    val codec = VideoCodecManager.PreferredCodec.values()
                        .find { it.displayName == newValue }
                    if (codec != null) {
                        VideoCodecManager.savePreferredCodec(context, codec)
                    }
                }
            )
        }

        // Ensure last item isn't squished behind nav bar
        Spacer(modifier = Modifier.height(16.dp))
        
        // Manual FCM Token Refresh Button
        var fcmRefreshStatus by remember { mutableStateOf("") }
        
        Button(
            onClick = {
                fcmRefreshStatus = "Refreshing..."
                com.google.firebase.messaging.FirebaseMessaging.getInstance().token
                    .addOnSuccessListener { token ->
                        val currentUser = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
                        if (currentUser != null) {
                            com.google.firebase.firestore.FirebaseFirestore.getInstance()
                                .collection("users")
                                .document(currentUser.uid)
                                .set(
                                    hashMapOf(
                                        "fcmToken" to token,
                                        "lastTokenUpdate" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                                    ),
                                    com.google.firebase.firestore.SetOptions.merge()
                                )
                                .addOnSuccessListener {
                                    fcmRefreshStatus = "✅ Token refreshed!"
                                }
                                .addOnFailureListener { e ->
                                    fcmRefreshStatus = "❌ Failed: ${e.message}"
                                }
                        } else {
                            fcmRefreshStatus = "❌ Not logged in"
                        }
                    }
                    .addOnFailureListener { e ->
                        fcmRefreshStatus = "❌ Error: ${e.message}"
                    }
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryBlue)
        ) {
            Text("Refresh Push Notification Token", color = Color.White)
        }
        
        if (fcmRefreshStatus.isNotEmpty()) {
            Text(
                text = fcmRefreshStatus,
                color = if (fcmRefreshStatus.startsWith("✅")) Color.Green else Color.Red,
                fontSize = 12.sp,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )
        }
        
        Spacer(modifier = Modifier.height(32.dp))
        
        // Version info
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            val versionName = try {
                context.packageManager.getPackageInfo(context.packageName, 0).versionName
            } catch (e: Exception) {
                "Unknown"
            }
            Text(
                text = "Version $versionName",
                color = AppColors.TextLight.copy(alpha = 0.5f),
                fontSize = 12.sp
            )
        }
        
        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
fun SettingsSwitch(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppColors.Gray.copy(alpha = 0.1f))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, color = AppColors.TextLight, fontSize = 16.sp)
            Text(text = subtitle, color = AppColors.TextLight.copy(alpha = 0.7f), fontSize = 14.sp)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = AppColors.PrimaryBlue,
                checkedTrackColor = AppColors.PrimaryBlue.copy(alpha = 0.5f)
            )
        )
    }
}

@Composable
fun SettingsDropdown(
    title: String,
    subtitle: String,
    selectedValue: String,
    options: List<String>,
    onValueChange: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppColors.Gray.copy(alpha = 0.1f))
            .clickable { expanded = true }
            .padding(16.dp)
    ) {
        Text(text = title, color = AppColors.TextLight, fontSize = 16.sp)
        Text(text = subtitle, color = AppColors.TextLight.copy(alpha = 0.7f), fontSize = 14.sp)
        Text(text = selectedValue, color = AppColors.PrimaryBlue, fontSize = 14.sp)

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            modifier = Modifier.background(AppColors.BackgroundDark.copy(alpha = 0.95f))
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(text = option, color = AppColors.TextLight) },
                    onClick = {
                        onValueChange(option)
                        expanded = false
                    }
                )
            }
        }
    }
}