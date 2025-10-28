package com.example.tres3.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tres3.ar.ARFiltersManager
import com.example.tres3.chat.InCallChatManager
import com.example.tres3.effects.BackgroundEffectsLibrary
import com.example.tres3.layout.MultiStreamLayoutManager
import com.example.tres3.reactions.ReactionManager
import com.example.tres3.video.LowLightEnhancer
import java.text.SimpleDateFormat
import java.util.*

/**
 * ControlPanelBottomSheets - Compose UI components for all in-call controls
 * 
 * Usage in InCallActivity Compose:
 * ```kotlin
 * var showChatSheet by remember { mutableStateOf(false) }
 * 
 * if (showChatSheet) {
 *     ChatBottomSheet(
 *         messages = coordinator.chatMessages.collectAsState().value,
 *         onSendMessage = { coordinator.sendChatMessage(it) },
 *         onDismiss = { showChatSheet = false }
 *     )
 * }
 * ```
 */

/**
 * Chat Bottom Sheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatBottomSheet(
    messages: List<InCallChatManager.ChatMessage>,
    onSendMessage: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var messageText by remember { mutableStateOf("") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF1C1C1E)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Chat",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Messages list
            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(messages) { message ->
                    ChatMessageItem(message)
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Input field
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = messageText,
                    onValueChange = { messageText = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Type a message...") },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedBorderColor = Color(0xFF0A84FF),
                        unfocusedBorderColor = Color.Gray
                    )
                )

                Spacer(modifier = Modifier.width(8.dp))

                IconButton(
                    onClick = {
                        if (messageText.isNotBlank()) {
                            onSendMessage(messageText)
                            messageText = ""
                        }
                    }
                ) {
                    Icon(
                        imageVector = Icons.Default.Send,
                        contentDescription = "Send",
                        tint = Color(0xFF0A84FF)
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun ChatMessageItem(message: InCallChatManager.ChatMessage) {
    val dateFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF2C2C2E), RoundedCornerShape(8.dp))
            .padding(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = message.senderId,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF0A84FF)
            )
            Text(
                text = dateFormat.format(Date(message.timestamp)),
                fontSize = 12.sp,
                color = Color.Gray
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = message.message,
            fontSize = 14.sp,
            color = Color.White
        )
    }
}

/**
 * Reactions Bottom Sheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReactionsBottomSheet(
    onReaction: (ReactionManager.ReactionType) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF1C1C1E)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp)
        ) {
            Text(
                text = "Quick Reactions",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Reaction grid
            Column(
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    ReactionButton("❤️", ReactionManager.ReactionType.HEART, onReaction)
                    ReactionButton("😂", ReactionManager.ReactionType.LAUGH, onReaction)
                    ReactionButton("👏", ReactionManager.ReactionType.CLAP, onReaction)
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    ReactionButton("🎉", ReactionManager.ReactionType.PARTY, onReaction)
                    ReactionButton("😮", ReactionManager.ReactionType.SURPRISED, onReaction)
                    ReactionButton("👍", ReactionManager.ReactionType.THUMBS_UP, onReaction)
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun ReactionButton(
    emoji: String,
    type: ReactionManager.ReactionType,
    onClick: (ReactionManager.ReactionType) -> Unit
) {
    Button(
        onClick = { onClick(type) },
        modifier = Modifier.size(80.dp),
        shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color(0xFF2C2C2E)
        )
    ) {
        Text(
            text = emoji,
            fontSize = 36.sp
        )
    }
}

/**
 * Effects Bottom Sheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EffectsBottomSheet(
    currentEffect: BackgroundEffectsLibrary.BlurIntensity,
    onEffectSelect: (BackgroundEffectsLibrary.BlurIntensity) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF1C1C1E)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Background Effects",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(16.dp))

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    EffectItem("None", "No blur") {
                        onEffectSelect(BackgroundEffectsLibrary.BlurIntensity.LIGHT)
                    }
                }
                item {
                    EffectItem("Light Blur", "Soft background blur") {
                        onEffectSelect(BackgroundEffectsLibrary.BlurIntensity.LIGHT)
                    }
                }
                item {
                    EffectItem("Medium Blur", "Moderate background blur") {
                        onEffectSelect(BackgroundEffectsLibrary.BlurIntensity.MEDIUM)
                    }
                }
                item {
                    EffectItem("Heavy Blur", "Strong background blur") {
                        onEffectSelect(BackgroundEffectsLibrary.BlurIntensity.HEAVY)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun EffectItem(
    title: String,
    description: String,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        color = Color(0xFF2C2C2E),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Text(
                text = title,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Text(
                text = description,
                fontSize = 14.sp,
                color = Color.Gray
            )
        }
    }
}

/**
 * AR Filters Bottom Sheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ARFiltersBottomSheet(
    currentFilter: ARFiltersManager.ARFilter,
    onFilterSelect: (ARFiltersManager.ARFilter) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF1C1C1E)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "AR Filters",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(16.dp))

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(ARFiltersManager.ARFilter.values().toList()) { filter ->
                    FilterItem(
                        filter = filter,
                        isSelected = filter == currentFilter,
                        onClick = { onFilterSelect(filter) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun FilterItem(
    filter: ARFiltersManager.ARFilter,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        color = if (isSelected) Color(0xFF0A84FF) else Color(0xFF2C2C2E),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = filter.name.replace("_", " ").lowercase().replaceFirstChar { it.uppercase() },
                fontSize = 16.sp,
                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                color = Color.White
            )
        }
    }
}

/**
 * Layout Options Bottom Sheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LayoutOptionsBottomSheet(
    currentLayout: MultiStreamLayoutManager.LayoutMode,
    onLayoutSelect: (MultiStreamLayoutManager.LayoutMode) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF1C1C1E)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Layout Mode",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(16.dp))

            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                LayoutOption("Grid", "Equal tiles", currentLayout == MultiStreamLayoutManager.LayoutMode.GRID) {
                    onLayoutSelect(MultiStreamLayoutManager.LayoutMode.GRID)
                }
                LayoutOption("Spotlight", "Featured + thumbnails", currentLayout == MultiStreamLayoutManager.LayoutMode.SPOTLIGHT) {
                    onLayoutSelect(MultiStreamLayoutManager.LayoutMode.SPOTLIGHT)
                }
                LayoutOption("Picture-in-Picture", "Main + overlay", currentLayout == MultiStreamLayoutManager.LayoutMode.PIP) {
                    onLayoutSelect(MultiStreamLayoutManager.LayoutMode.PIP)
                }
                LayoutOption("Sidebar", "Main + side gallery", currentLayout == MultiStreamLayoutManager.LayoutMode.SIDEBAR) {
                    onLayoutSelect(MultiStreamLayoutManager.LayoutMode.SIDEBAR)
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun LayoutOption(
    title: String,
    description: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        color = if (isSelected) Color(0xFF0A84FF) else Color(0xFF2C2C2E),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Text(
                text = title,
                fontSize = 16.sp,
                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                color = Color.White
            )
            Text(
                text = description,
                fontSize = 14.sp,
                color = if (isSelected) Color.White.copy(alpha = 0.8f) else Color.Gray
            )
        }
    }
}

/**
 * Settings Bottom Sheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsBottomSheet(
    spatialAudioEnabled: Boolean,
    lowLightMode: LowLightEnhancer.EnhancementMode,
    onSpatialAudioToggle: (Boolean) -> Unit,
    onLowLightModeChange: (LowLightEnhancer.EnhancementMode) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF1C1C1E)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Settings",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Spatial Audio Toggle
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Spatial Audio", color = Color.White, fontSize = 16.sp)
                Switch(
                    checked = spatialAudioEnabled,
                    onCheckedChange = onSpatialAudioToggle
                )
            }

            Divider(color = Color.Gray, modifier = Modifier.padding(vertical = 8.dp))

            // Low Light Mode
            Text("Low-Light Enhancement", color = Color.White, fontSize = 16.sp)
            Spacer(modifier = Modifier.height(8.dp))

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                LowLightEnhancer.EnhancementMode.values().forEach { mode ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onLowLightModeChange(mode) }
                            .background(
                                if (lowLightMode == mode) Color(0xFF0A84FF) else Color.Transparent,
                                RoundedCornerShape(8.dp)
                            )
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = lowLightMode == mode,
                            onClick = { onLowLightModeChange(mode) }
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(mode.name, color = Color.White, fontSize = 14.sp)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}
