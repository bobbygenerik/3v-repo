package com.example.tres3

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
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
            title = "Heads-up Notifications Only",
            subtitle = "Show drop-down notification instead of full-screen",
            checked = headsUpNotifications,
            onCheckedChange = { newValue ->
                headsUpNotifications = newValue
                sharedPrefs.edit().putBoolean("heads_up_notifications", newValue).apply()
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Call Quality Dropdown
        SettingsDropdown(
            title = "Call Quality",
            subtitle = "Select video quality",
            selectedValue = callQuality,
            options = listOf("Low", "Auto", "High"),
            onValueChange = { newValue ->
                callQuality = newValue
                sharedPrefs.edit().putString("call_quality", newValue).apply()
            }
        )
        
        // Advanced Codec Selection (only if feature flag enabled)
        if (advancedCodecsEnabled && availableCodecs.size > 1) {
            Spacer(modifier = Modifier.height(16.dp))
            
            SettingsDropdown(
                title = "Video Codec",
                subtitle = "Advanced: Select video encoder (${availableCodecs.size} supported)",
                selectedValue = selectedCodec,
                options = availableCodecs,
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