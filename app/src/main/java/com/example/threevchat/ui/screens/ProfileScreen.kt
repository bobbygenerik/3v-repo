package com.example.threevchat.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.CachePolicy
import coil.request.ImageRequest
import com.example.threevchat.ui.theme.AppColors
import com.example.threevchat.ui.theme.AppTypography
import com.example.threevchat.ui.components.GradientFocusWrapper
import com.example.threevchat.ui.components.GradientCtaButton
import com.example.threevchat.viewmodel.MainViewModel
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.UserProfileChangeRequest
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

@Composable
fun ProfileScreen(vm: MainViewModel, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    val auth = FirebaseAuth.getInstance()
    
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var displayName by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var bio by remember { mutableStateOf("") }
    var photoUrl by remember { mutableStateOf<String?>(null) }
    var uploadingPhoto by remember { mutableStateOf(false) }
    
    var nameFocused by remember { mutableStateOf(false) }
    var userFocused by remember { mutableStateOf(false) }
    var bioFocused by remember { mutableStateOf(false) }

    // Load existing profile data
    LaunchedEffect(Unit) {
        loading = true
        val repo = com.example.threevchat.data.UserRepository(
            (ctx.applicationContext as android.app.Application)
        )
        val result = repo.getProfile()
        if (result.isSuccess) {
            val profile = result.getOrNull()
            displayName = profile?.displayName ?: ""
            username = profile?.username ?: ""
            bio = profile?.bio ?: ""
            photoUrl = profile?.photoUrl
        } else {
            error = result.exceptionOrNull()?.message
        }
        loading = false
    }

    val pickImage = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            scope.launch {
                uploadingPhoto = true
                error = null
                val repo = com.example.threevchat.data.UserRepository(
                    (ctx.applicationContext as android.app.Application)
                )
                val res = repo.uploadProfilePhoto(uri)
                if (res.isSuccess) {
                    photoUrl = res.getOrNull()
                    
                    // Update Firebase Auth profile too
                    try {
                        val profileUpdates = UserProfileChangeRequest.Builder()
                            .setPhotoUri(Uri.parse(photoUrl))
                            .build()
                        auth.currentUser?.updateProfile(profileUpdates)?.await()
                    } catch (e: Exception) {
                        // Non-critical, just log
                    }
                } else {
                    error = res.exceptionOrNull()?.message
                }
                uploadingPhoto = false
            }
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
            .padding(24.dp)
    ) {
        if (loading) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center),
                color = Color(0xFF3CB371)
            )
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Top
            ) {
                Spacer(modifier = Modifier.height(32.dp))
                
                Text(
                    text = "Edit Profile",
                    fontFamily = AppTypography.displayLarge.fontFamily ?: FontFamily.Default,
                    fontWeight = FontWeight.Bold,
                    fontSize = 28.sp,
                    color = Color.White
                )
                
                Spacer(modifier = Modifier.height(32.dp))
                
                // Profile photo
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape)
                        .clickable { pickImage.launch("image/*") }
                ) {
                    if (photoUrl != null) {
                        val request = ImageRequest.Builder(ctx)
                            .data(photoUrl)
                            .diskCachePolicy(CachePolicy.DISABLED)
                            .memoryCachePolicy(CachePolicy.DISABLED)
                            .build()
                        AsyncImage(
                            model = request,
                            contentDescription = "Profile photo",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Crop
                        )
                    } else {
                        Surface(
                            shape = CircleShape,
                            color = Color.White.copy(alpha = 0.1f),
                            modifier = Modifier.fillMaxSize()
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Text(
                                    "Add Photo",
                                    color = AppColors.TextSecondary,
                                    fontSize = 14.sp
                                )
                            }
                        }
                    }
                    
                    if (uploadingPhoto) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .size(40.dp)
                                .align(Alignment.Center),
                            color = Color(0xFF3CB371)
                        )
                    }
                }
                
                Spacer(modifier = Modifier.height(16.dp))
                
                TextButton(onClick = { pickImage.launch("image/*") }) {
                    Text("Change Photo", color = Color.White, fontWeight = FontWeight.SemiBold)
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Display name
                GradientFocusWrapper(isGlowing = nameFocused) {
                    OutlinedTextField(
                        value = displayName,
                        onValueChange = { displayName = it },
                        placeholder = { Text("Display name", color = AppColors.TextSecondary) },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .onFocusChanged { nameFocused = it.isFocused },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color.Transparent,
                            unfocusedBorderColor = Color.Transparent,
                            focusedContainerColor = Color(0xFF1A1A1A),
                            unfocusedContainerColor = Color(0xFF1A1A1A),
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Username
                GradientFocusWrapper(isGlowing = userFocused) {
                    OutlinedTextField(
                        value = username,
                        onValueChange = { username = it },
                        placeholder = { Text("Username", color = AppColors.TextSecondary) },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .onFocusChanged { userFocused = it.isFocused },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color.Transparent,
                            unfocusedBorderColor = Color.Transparent,
                            focusedContainerColor = Color(0xFF1A1A1A),
                            unfocusedContainerColor = Color(0xFF1A1A1A),
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Bio
                GradientFocusWrapper(isGlowing = bioFocused) {
                    OutlinedTextField(
                        value = bio,
                        onValueChange = { bio = it },
                        placeholder = { Text("Bio", color = AppColors.TextSecondary) },
                        minLines = 3,
                        modifier = Modifier
                            .fillMaxWidth()
                            .onFocusChanged { bioFocused = it.isFocused },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color.Transparent,
                            unfocusedBorderColor = Color.Transparent,
                            focusedContainerColor = Color(0xFF1A1A1A),
                            unfocusedContainerColor = Color(0xFF1A1A1A),
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                }

                Spacer(modifier = Modifier.height(24.dp))

                if (error != null) {
                    Text(error!!, color = MaterialTheme.colorScheme.error)
                    Spacer(modifier = Modifier.height(16.dp))
                }

                // Save button
                GradientCtaButton(
                    text = "Save",
                    onClick = {
                        scope.launch {
                            loading = true
                            error = null
                            
                            val repo = com.example.threevchat.data.UserRepository(
                                (ctx.applicationContext as android.app.Application)
                            )
                            
                            // Update Firestore profile
                            val up = repo.updateProfile(
                                displayName = displayName.ifBlank { null },
                                bio = bio.ifBlank { null }
                            )
                            
                            // Claim username if changed
                            val currentProfile = repo.getProfile().getOrNull()
                            val unameRes = if (
                                username.isNotBlank() &&
                                username.trim().lowercase() != currentProfile?.username?.trim()?.lowercase()
                            ) {
                                repo.claimUsernameForCurrentUser(username)
                            } else Result.success(Unit)
                            
                            // Update Firebase Auth displayName
                            try {
                                if (displayName.isNotBlank()) {
                                    val profileUpdates = UserProfileChangeRequest.Builder()
                                        .setDisplayName(displayName)
                                        .apply {
                                            photoUrl?.let { setPhotoUri(Uri.parse(it)) }
                                        }
                                        .build()
                                    auth.currentUser?.updateProfile(profileUpdates)?.await()
                                }
                            } catch (e: Exception) {
                                // Non-critical
                            }
                            
                            error = up.exceptionOrNull()?.message ?: unameRes.exceptionOrNull()?.message
                            loading = false
                            
                            if (error == null) {
                                onBack()
                            }
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                )
                
                Spacer(modifier = Modifier.height(16.dp))
                
                TextButton(onClick = onBack) {
                    Text("Cancel", color = Color.White.copy(alpha = 0.7f))
                }
            }
        }
    }
}