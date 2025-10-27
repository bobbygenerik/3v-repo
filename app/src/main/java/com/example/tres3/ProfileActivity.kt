package com.example.tres3

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import coil.compose.AsyncImage
import com.example.tres3.AppColors
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

class ProfileActivity : AppCompatActivity() {
    private fun loadProfileData(onComplete: (String, String?) -> Unit) {
        val currentUser = auth.currentUser ?: return
        firestore.collection("users").document(currentUser.uid)
            .get()
            .addOnSuccessListener { document ->
                val name = document.getString("displayName") ?: ""
                val photoUrl = document.getString("photoUrl")
                onComplete(name, photoUrl)
            }
            .addOnFailureListener {
                onComplete("", null)
            }
    }

    private lateinit var auth: FirebaseAuth
    private lateinit var firestore: FirebaseFirestore
    private lateinit var storage: FirebaseStorage

    private val pickImageLauncher = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri?.let { 
            uploadProfilePicture(it)
        }
    }
    
    private fun uploadProfilePicture(uri: Uri) {
        val currentUser = auth.currentUser ?: return
        
        Log.d("ProfileActivity", "📸 Starting profile picture upload for user: ${currentUser.uid}")
        Log.d("ProfileActivity", "   Image URI: $uri")
        
        Toast.makeText(this, "Uploading profile picture...", Toast.LENGTH_SHORT).show()
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Upload to Firebase Storage
                val storageRef = storage.reference
                    .child("profile_pictures/${currentUser.uid}/${System.currentTimeMillis()}.jpg")
                
                Log.d("ProfileActivity", "   Uploading to Storage path: ${storageRef.path}")
                storageRef.putFile(uri).await()
                
                val downloadUrl = storageRef.downloadUrl.await().toString()
                Log.d("ProfileActivity", "   ✅ Upload complete! Download URL: $downloadUrl")
                
                // Update Firestore with new photo URL
                Log.d("ProfileActivity", "   Updating Firestore users/${currentUser.uid} with photoUrl")
                firestore.collection("users").document(currentUser.uid)
                    .update("photoUrl", downloadUrl)
                    .await()
                
                Log.d("ProfileActivity", "   ✅ Firestore updated successfully")
                
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@ProfileActivity, "Profile picture updated!", Toast.LENGTH_SHORT).show()
                    // Trigger UI refresh by recreating activity
                    recreate()
                }
            } catch (e: Exception) {
                Log.e("ProfileActivity", "❌ Failed to upload profile picture", e)
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@ProfileActivity, "Failed to upload: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable edge-to-edge
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }

        auth = FirebaseAuth.getInstance()
        firestore = FirebaseFirestore.getInstance()
        storage = FirebaseStorage.getInstance()

        val currentUser = auth.currentUser
        if (currentUser == null) {
            startActivity(Intent(this, SignInActivity::class.java))
            finish()
            return
        }

        setContent {
            ProfileScreen()
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun ProfileScreen() {
        var displayName by remember { mutableStateOf("") }
        var profilePhotoUrl by remember { mutableStateOf<String?>(null) }
        var isLoading by remember { mutableStateOf(true) }
        var isSaving by remember { mutableStateOf(false) }
        val currentUser = auth.currentUser

        // Load profile data
        LaunchedEffect(Unit) {
            loadProfileData { name, photoUrl ->
                displayName = name
                profilePhotoUrl = photoUrl
                isLoading = false
            }
        }

        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            "Profile Settings",
                            color = AppColors.TextLight,
                            fontWeight = FontWeight.Bold
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = { finish() }) {
                            Icon(
                                painter = painterResource(id = R.drawable.ic_arrow_up),
                                contentDescription = "Back",
                                tint = AppColors.TextLight
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.BackgroundDark
                    )
                )
            },
            containerColor = AppColors.BackgroundDark
        ) { paddingValues ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                if (isLoading) {
                    CircularProgressIndicator(color = AppColors.PrimaryBlue)
                } else {
                    // Profile Image Section with border
                    Box(
                        modifier = Modifier
                            .size(120.dp)
                            .border(
                                width = 3.dp,
                                color = AppColors.PrimaryBlue,
                                shape = CircleShape
                            )
                            .clip(CircleShape)
                            .background(AppColors.Gray.copy(alpha = 0.2f))
                            .clickable { pickImageLauncher.launch("image/*") },
                        contentAlignment = Alignment.Center
                    ) {
                        if (profilePhotoUrl != null) {
                            AsyncImage(
                                model = profilePhotoUrl,
                                contentDescription = "Profile Picture",
                                modifier = Modifier
                                    .size(114.dp)
                                    .clip(CircleShape),
                                contentScale = ContentScale.Crop
                            )
                        } else {
                            val initials = getInitials(displayName)
                            Text(
                                text = initials,
                                color = AppColors.TextLight,
                                fontWeight = FontWeight.Bold,
                                fontSize = 32.sp
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    Text(
                        "Tap to change profile picture",
                        color = AppColors.TextLight.copy(alpha = 0.7f),
                        fontSize = 14.sp
                    )

                    Spacer(modifier = Modifier.height(48.dp))

                    // Display Name Input - matches other screens
                    OutlinedTextField(
                        value = displayName,
                        onValueChange = { displayName = it },
                        label = { Text("Display Name") },
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = AppColors.PrimaryBlue,
                            unfocusedBorderColor = AppColors.Gray,
                            focusedLabelColor = AppColors.PrimaryBlue,
                            unfocusedLabelColor = AppColors.TextLight,
                            cursorColor = AppColors.PrimaryBlue,
                            focusedContainerColor = AppColors.BackgroundDark,
                            unfocusedContainerColor = AppColors.BackgroundDark,
                            focusedTextColor = AppColors.TextLight,
                            unfocusedTextColor = AppColors.TextLight
                        ),
                        modifier = Modifier.fillMaxWidth()
                    )

                    Spacer(modifier = Modifier.height(32.dp))

                    // Save Button - matches other screens (56dp height)
                    Button(
                        onClick = {
                            if (displayName.trim().isNotEmpty()) {
                                isSaving = true
                                saveProfileData(displayName.trim()) { success ->
                                    isSaving = false
                                    if (success) {
                                        Toast.makeText(this@ProfileActivity, "Profile saved successfully!", Toast.LENGTH_SHORT).show()
                                        finish()
                                    } else {
                                        Toast.makeText(this@ProfileActivity, "Failed to save profile", Toast.LENGTH_SHORT).show()
                                    }
                                }
                            }
                        },
                        enabled = !isSaving && displayName.trim().isNotEmpty(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = AppColors.PrimaryBlue,
                            disabledContainerColor = AppColors.Gray
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp)
                    ) {
                        if (isSaving) {
                            CircularProgressIndicator(
                                color = Color.White,
                                modifier = Modifier.size(20.dp)
                            )
                        } else {
                            Text(
                                "Save Profile",
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 16.sp
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(24.dp))
                }
            }
        }
    }

    private fun getInitials(name: String): String {
        val parts = name.trim().split(" ")
        return when {
            parts.size >= 2 -> (parts[0].firstOrNull()?.toString() ?: "") + (parts[1].firstOrNull()?.toString() ?: "")
            parts.size == 1 -> parts[0].take(2)
            else -> "JD"
        }.uppercase()
    }

    private fun saveProfileData(newDisplayName: String, onComplete: (Boolean) -> Unit) {
        val currentUser = auth.currentUser ?: return
        val updates = hashMapOf<String, Any>(
            "displayName" to newDisplayName,
            "email" to (currentUser.email ?: "")
        )
        firestore.collection("users").document(currentUser.uid)
            .update(updates)
            .addOnSuccessListener {
                val sharedPreferences = getSharedPreferences("Tres3Prefs", Context.MODE_PRIVATE)
                val editor = sharedPreferences.edit()
                editor.putString("displayName", newDisplayName)
                editor.apply()
                onComplete(true)
            }
            .addOnFailureListener {
                onComplete(false)
            }
    }
}