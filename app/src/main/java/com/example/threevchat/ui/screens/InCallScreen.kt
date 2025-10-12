package com.example.threevchat.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.PopupProperties
import androidx.compose.animation.core.*
import kotlinx.coroutines.delay

@Composable
fun InCallScreen(
    contactName: String,
    onMenu: () -> Unit,
    onToggleMic: () -> Unit,
    isMicMuted: Boolean,
    onEndCall: () -> Unit,
    onSwitchCamera: () -> Unit,
    onAddPerson: () -> Unit,
    transparentBackground: Boolean = true,
    showVideoPlaceholder: Boolean = false,
    showSelfPip: Boolean = true,
    selfPipContent: (@Composable () -> Unit)? = null,
    showConnecting: Boolean = false
) {
    var pillVisible by remember { mutableStateOf(true) }
    var lastInteraction by remember { mutableStateOf(System.currentTimeMillis()) }
    
    LaunchedEffect(lastInteraction, showConnecting) {
        if (!showConnecting) {
            delay(3000)
            pillVisible = false
        }
    }

    val pillOffset by animateDpAsState(
        targetValue = if (pillVisible) 0.dp else 150.dp,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessLow
        ),
        label = "pill-slide"
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        Color(0xFF0A0F2B),
                        Color(0xFF102A43),
                        Color(0xFF0B2C5D)
                    )
                )
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                pillVisible = !pillVisible
                lastInteraction = System.currentTimeMillis()
            }
    ) {
        // Background initials
        if (showConnecting || !showVideoPlaceholder) {
            Box(
                modifier = Modifier.fillMaxSize().background(Color(0xFF1A1A1A)),
                contentAlignment = Alignment.Center
            ) {
                val initials = contactName.split(" ", "@", ".")
                    .filter { it.isNotBlank() }
                    .map { it.first().uppercaseChar() }
                    .joinToString("")
                    .take(2)
                    .ifEmpty { "?" }
                
                Box(
                    modifier = Modifier
                        .size(160.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = initials,
                        fontSize = 64.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }
        }
        
        // Connecting indicator
        if (showConnecting) {
            Box(
                modifier = Modifier.fillMaxSize().padding(top = 100.dp),
                contentAlignment = Alignment.TopCenter
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = Color(0xFF3CB371))
                    Spacer(Modifier.height(16.dp))
                    Text("Connecting...", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        // PIP - shows camera feed
        if (!showConnecting && showSelfPip && selfPipContent != null) {
            var pipExpanded by remember { mutableStateOf(false) }
            val pipWidth by animateDpAsState(
                targetValue = if (pipExpanded) 180.dp else 96.dp,
                animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy),
                label = "pip-width"
            )
            val pipHeight by animateDpAsState(
                targetValue = if (pipExpanded) 240.dp else 128.dp,
                animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy),
                label = "pip-height"
            )
            
            Box(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 16.dp, bottom = 140.dp)
                    .size(width = pipWidth, height = pipHeight)
                    .clip(RoundedCornerShape(12.dp))
                    .clickable { pipExpanded = !pipExpanded }
                    .graphicsLayer { alpha = if (pillVisible) 1f else 0.3f }
            ) {
                selfPipContent()
            }
        }

        // Top bar
        if (!showConnecting) {
            var callDuration by remember { mutableStateOf(0) }
            
            LaunchedEffect(Unit) {
                while (true) {
                    delay(1000)
                    callDuration++
                }
            }
            
            val minutes = callDuration / 60
            val seconds = callDuration % 60
            val timeString = String.format("%02d:%02d", minutes, seconds)
            
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 48.dp)
                    .graphicsLayer { alpha = if (pillVisible) 1f else 0f }
            ) {
                Column {
                    Text(contactName, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(4.dp))
                    Text(timeString, color = Color.White.copy(alpha = 0.7f), fontSize = 14.sp)
                }
            }
        }

        // Bottom controls
        if (!showConnecting) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .offset(y = pillOffset)
                    .padding(bottom = 24.dp)
            ) {
                Surface(
                    shape = RoundedCornerShape(32.dp),
                    color = Color.White.copy(alpha = 0.15f),
                    modifier = Modifier.clip(RoundedCornerShape(32.dp))
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // Menu button
                        var showMenu by remember { mutableStateOf(false) }
                        Box {
                            IconButton(
                                onClick = { 
                                    showMenu = !showMenu
                                    pillVisible = true
                                    lastInteraction = System.currentTimeMillis()
                                },
                                modifier = Modifier
                                    .size(48.dp)
                                    .clip(CircleShape)
                                    .background(Color.White.copy(alpha = 0.2f))
                            ) {
                                Box(modifier = Modifier.size(16.dp)) {
                                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                            Box(Modifier.size(6.dp).background(Color.White, RoundedCornerShape(1.dp)))
                                            Box(Modifier.size(6.dp).background(Color.White, RoundedCornerShape(1.dp)))
                                        }
                                        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                            Box(Modifier.size(6.dp).background(Color.White, RoundedCornerShape(1.dp)))
                                            Box(Modifier.size(6.dp).background(Color.White, RoundedCornerShape(1.dp)))
                                        }
                                    }
                                }
                            }
                            
                            // Transparent menu
                            Box {
                                DropdownMenu(
                                    expanded = showMenu,
                                    onDismissRequest = { showMenu = false },
                                    modifier = Modifier.background(Color.Transparent),
                                    properties = PopupProperties(focusable = true)
                                ) {
                                    Surface(
                                        modifier = Modifier.fillMaxWidth(),
                                        color = Color(0xFF1E1E1E).copy(alpha = 0.95f),
                                        shape = RoundedCornerShape(12.dp)
                                    ) {
                                        Column(modifier = Modifier.padding(vertical = 4.dp)) {
                                            DropdownMenuItem(
                                                text = { Text("Settings", color = Color.White) },
                                                onClick = { 
                                                    showMenu = false
                                                    onMenu()
                                                },
                                                colors = MenuDefaults.itemColors(textColor = Color.White)
                                            )
                                            DropdownMenuItem(
                                                text = { Text("Add Person", color = Color.White) },
                                                onClick = { 
                                                    showMenu = false
                                                    onAddPerson()
                                                },
                                                colors = MenuDefaults.itemColors(textColor = Color.White)
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        // Mic button
                        val micInteraction = remember { MutableInteractionSource() }
                        val micPressed by micInteraction.collectIsPressedAsState()
                        val micScale by animateFloatAsState(if (micPressed) 0.9f else 1f, label = "mic-scale")
                        IconButton(
                            onClick = { 
                                onToggleMic()
                                pillVisible = true
                                lastInteraction = System.currentTimeMillis()
                            },
                            interactionSource = micInteraction,
                            modifier = Modifier
                                .size(48.dp)
                                .scale(micScale)
                                .clip(CircleShape)
                                .background(if (isMicMuted) Color.Red else Color.White.copy(alpha = 0.2f))
                        ) {
                            Icon(
                                imageVector = if (isMicMuted) Icons.Default.MicOff else Icons.Default.Mic,
                                contentDescription = "Mic",
                                tint = Color.White
                            )
                        }

                        // End call button
                        val endInteraction = remember { MutableInteractionSource() }
                        val endPressed by endInteraction.collectIsPressedAsState()
                        val endScale by animateFloatAsState(if (endPressed) 0.9f else 1f, label = "end-scale")
                        IconButton(
                            onClick = onEndCall,
                            interactionSource = endInteraction,
                            modifier = Modifier
                                .size(64.dp)
                                .scale(endScale)
                                .clip(CircleShape)
                                .background(Color.Red)
                        ) {
                            Icon(
                                imageVector = Icons.Default.CallEnd,
                                contentDescription = "End Call",
                                tint = Color.White,
                                modifier = Modifier.size(32.dp)
                            )
                        }

                        // Switch camera button
                        val camInteraction = remember { MutableInteractionSource() }
                        val camPressed by camInteraction.collectIsPressedAsState()
                        val camScale by animateFloatAsState(if (camPressed) 0.9f else 1f, label = "cam-scale")
                        IconButton(
                            onClick = { 
                                onSwitchCamera()
                                pillVisible = true
                                lastInteraction = System.currentTimeMillis()
                            },
                            interactionSource = camInteraction,
                            modifier = Modifier
                                .size(48.dp)
                                .scale(camScale)
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.2f))
                        ) {
                            Icon(
                                imageVector = Icons.Default.Cameraswitch,
                                contentDescription = "Switch Camera",
                                tint = Color.White
                            )
                        }

                        // Add person button
                        val addInteraction = remember { MutableInteractionSource() }
                        val addPressed by addInteraction.collectIsPressedAsState()
                        val addScale by animateFloatAsState(if (addPressed) 0.9f else 1f, label = "add-scale")
                        IconButton(
                            onClick = { 
                                onAddPerson()
                                pillVisible = true
                                lastInteraction = System.currentTimeMillis()
                            },
                            interactionSource = addInteraction,
                            modifier = Modifier
                                .size(48.dp)
                                .scale(addScale)
                                .clip(CircleShape)
                                .background(Color(0xFF3CB371))
                        ) {
                            Icon(
                                imageVector = Icons.Default.PersonAdd,
                                contentDescription = "Add Person",
                                tint = Color.White
                            )
                        }
                    }
                }
            }
        }
    }
}