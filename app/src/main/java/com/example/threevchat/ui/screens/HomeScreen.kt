package com.example.threevchat.ui.screens

import android.Manifest
import android.content.Intent
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Contacts
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import com.example.threevchat.ui.theme.AppColors
import com.example.threevchat.ui.theme.AppTypography
import com.example.threevchat.ui.components.GradientFocusWrapper
import com.example.threevchat.ui.components.GradientPressButton
import com.example.threevchat.ui.components.GradientCtaButton
import com.example.threevchat.viewmodel.MainViewModel

private val montserratFontFamily: FontFamily 
    get() = AppTypography.displayLarge.fontFamily ?: FontFamily.Default
private val interFontFamily: FontFamily 
    get() = AppTypography.bodyLarge.fontFamily ?: FontFamily.Default

@Composable
fun HomeScreen(
    displayName: String?,
    profileUrl: String?,
    onOpenProfile: () -> Unit,
    onOpenSettings: () -> Unit,
    onSignOut: () -> Unit,
    onViewCallLogs: () -> Unit,
    vm: MainViewModel? = null
) {
    val ctx = LocalContext.current
    
    var callee by remember { mutableStateOf("") }
    var showProfileMenu by remember { mutableStateOf(false) }
    var searchFocused by remember { mutableStateOf(false) }
    var welcomeAlpha by remember { mutableStateOf(0f) }
    var welcomeOffset by remember { mutableStateOf(20f) }
    
    val contactsLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            val intent = Intent(Intent.ACTION_PICK, android.provider.ContactsContract.Contacts.CONTENT_URI)
            ctx.startActivity(intent)
        } else {
            Toast.makeText(ctx, "Contacts permission denied", Toast.LENGTH_SHORT).show()
        }
    }
    
    LaunchedEffect(Unit) {
        delay(200)
        animate(0f, 1f, animationSpec = tween(1500, easing = FastOutSlowInEasing)) { value, _ ->
            welcomeAlpha = value
            welcomeOffset = 20f * (1f - value)
        }
    }

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
    ) {
        // Top bar with profile button
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 48.dp, end = 16.dp),
            horizontalArrangement = Arrangement.End
        ) {
            Box {
                IconButton(onClick = { showProfileMenu = true }) {
                    if (!profileUrl.isNullOrBlank()) {
                        AsyncImage(
                            model = profileUrl,
                            contentDescription = "Profile",
                            modifier = Modifier.size(36.dp).clip(CircleShape)
                        )
                    } else {
                        val initials = displayName?.split(" ", "@", ".")
                            ?.filter { it.isNotBlank() }
                            ?.map { it.first().uppercaseChar() }
                            ?.joinToString("")?.take(2) ?: "?"
                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.12f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = initials,
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 16.sp
                            )
                        }
                    }
                }
                
                // Semi-transparent dropdown menu - simplified
                DropdownMenu(
                    expanded = showProfileMenu,
                    onDismissRequest = { showProfileMenu = false }
                ) {
                    Surface(
                        color = Color(0xFF1E1E1E).copy(alpha = 0.95f),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Column(modifier = Modifier.padding(vertical = 4.dp)) {
                            DropdownMenuItem(
                                text = { Text("Profile", color = Color.White) },
                                onClick = { 
                                    showProfileMenu = false
                                    onOpenProfile() 
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Settings", color = Color.White) },
                                onClick = { 
                                    showProfileMenu = false
                                    onOpenSettings() 
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Sign out", color = Color(0xFFEF4444)) },
                                onClick = { 
                                    showProfileMenu = false
                                    onSignOut()
                                }
                            )
                        }
                    }
                }
            }
        }

        // Welcome message
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 120.dp)
                .offset(y = welcomeOffset.dp)
                .graphicsLayer { alpha = welcomeAlpha },
            contentAlignment = Alignment.Center
        ) {
            val firstName = displayName?.split(" ", "@", ".")
                ?.firstOrNull { it.isNotBlank() } ?: "User"
            
            Text(
                text = "Welcome, $firstName",
                color = Color.White,
                fontFamily = montserratFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 22.sp
            )
        }

        // Main content
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Search field
            GradientFocusWrapper(isGlowing = searchFocused) {
                OutlinedTextField(
                    value = callee,
                    onValueChange = { callee = it },
                    singleLine = true,
                    leadingIcon = { 
                        Text("@", color = AppColors.TextSecondary, fontSize = 20.sp)
                    },
                    placeholder = { Text("Search", color = AppColors.TextSecondary) },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color.Transparent,
                        unfocusedBorderColor = Color.Transparent,
                        focusedContainerColor = Color(0xFF1A1A1A),
                        unfocusedContainerColor = Color(0xFF1A1A1A),
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                    ),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { searchFocused = it.isFocused }
                )
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // Contacts and History buttons with gradient press effect
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Contacts Button
                GradientPressButton(
                    onClick = { contactsLauncher.launch(Manifest.permission.READ_CONTACTS) },
                    modifier = Modifier.weight(1f).height(56.dp),
                    backgroundColor = Color(0xFF1A1A1A)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Contacts,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = Color.White
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "Contacts",
                            fontFamily = interFontFamily,
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
                
                // History Button
                GradientPressButton(
                    onClick = { onViewCallLogs() },
                    modifier = Modifier.weight(1f).height(56.dp),
                    backgroundColor = Color(0xFF1A1A1A)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.History,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = Color.White
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "History",
                            fontFamily = interFontFamily,
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // Start Call button
            GradientCtaButton(
                text = "Start Call",
                onClick = {
                    if (callee.isBlank()) {
                        Toast.makeText(ctx, "Please enter a recipient", Toast.LENGTH_SHORT).show()
                    } else {
                        vm?.startCallTo(callee)
                        val uiState = vm?.uiState?.value
                        val sessionId = uiState?.currentRoom
                        if (sessionId != null) {
                            vm.launchCall(ctx, sessionId, "caller")
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().height(56.dp)
            )
        }
    }
}