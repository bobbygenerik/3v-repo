package com.example.tres3

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.*
import androidx.core.content.ContextCompat
import coil.compose.AsyncImage
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.util.Date
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import android.util.Log

// Contact data class
data class Contact(
    val id: String = "",
    val name: String = "",
    val email: String = "",
    val avatarUrl: String? = null,
    val isOnline: Boolean = false
)

@Composable
fun AnimatedTickerText(
    text: String,
    modifier: Modifier = Modifier,
    fontSize: TextUnit = 16.sp,
    color: Color = AppColors.TextLight
) {
    val letters = text.toList()
    
    Row(modifier = modifier) {
        letters.forEachIndexed { index, letter ->
            var startAnimation by remember(text) { mutableStateOf(false) }
            
            LaunchedEffect(text) {
                delay(index * 50L)
                startAnimation = true
            }
            
            val offsetY by animateFloatAsState(
                targetValue = if (startAnimation) 0f else 20f,
                animationSpec = tween(
                    durationMillis = 300,
                    easing = FastOutSlowInEasing
                ),
                label = "tickerLetter"
            )
            
            val alpha by animateFloatAsState(
                targetValue = if (startAnimation) 1f else 0f,
                animationSpec = tween(
                    durationMillis = 300,
                    easing = FastOutSlowInEasing
                ),
                label = "tickerAlpha"
            )
            
            Text(
                text = letter.toString(),
                fontSize = fontSize,
                color = color,
                modifier = Modifier
                    .offset(y = offsetY.dp)
                    .graphicsLayer(alpha = alpha)
            )
        }
    }
}

@Composable
fun MaterializeText(
    text: String,
    modifier: Modifier = Modifier,
    fontSize: TextUnit = 20.sp,
    fontWeight: FontWeight = FontWeight.Normal,
    color: Color = AppColors.TextLight
) {
    val fullText = text
    val charCount = fullText.length
    
    val visibleChars = remember { mutableStateListOf<Boolean>().apply { 
        repeat(charCount) { add(false) } 
    } }
    
    LaunchedEffect(text) {
        for (i in 0 until charCount) {
            delay(80) // Faster animation
            visibleChars[i] = true
        }
    }
    
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.Center
    ) {
        fullText.forEachIndexed { index, char ->
            val alpha by animateFloatAsState(
                targetValue = if (visibleChars.getOrElse(index) { false }) 1.0f else 0.0f,
                animationSpec = tween(durationMillis = 200, easing = EaseInOutCubic) // Faster fade-in
            )
            
            Text(
                text = char.toString(),
                fontSize = fontSize,
                fontWeight = fontWeight,
                color = color,
                modifier = Modifier.graphicsLayer(alpha = alpha)
            )
        }
    }
}

class HomeActivity : AppCompatActivity() {

    private lateinit var firestore: FirebaseFirestore
    private lateinit var auth: FirebaseAuth
    private val contacts = mutableStateListOf<Contact>()
    private val recentCalls = mutableStateListOf<com.example.tres3.data.CallHistory>()
    private lateinit var callHistoryRepository: com.example.tres3.data.CallHistoryRepository
    private var isCallSetupInProgress = false
    
    private var pendingContact: Contact? = null
    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.all { it.value }
        if (allGranted) {
            pendingContact?.let { initiateCallAfterPermissions(it) }
        } else {
            Toast.makeText(this, "Camera and microphone permissions are required for video calls", Toast.LENGTH_LONG).show()
        }
        pendingContact = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        auth = FirebaseAuth.getInstance()
        if (auth.currentUser == null) {
            startActivity(Intent(this, SignInActivity::class.java))
            finish()
            return
        }

        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }

        firestore = FirebaseFirestore.getInstance()
        callHistoryRepository = com.example.tres3.data.CallHistoryRepository()

        // Register phone account for native call UI
        TelecomHelper.registerPhoneAccount(this)
        
        // Request notification permission on Android 13+ for FCM
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) 
                != PackageManager.PERMISSION_GRANTED) {
                Log.w("HomeActivity", "⚠️ POST_NOTIFICATIONS permission not granted, requesting...")
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 999)
            } else {
                Log.d("HomeActivity", "✅ POST_NOTIFICATIONS permission already granted")
            }
        }

        // Register FCM token for push notifications
        registerFCMToken()

        // Request battery optimization exemption if needed
        if (BatteryOptimizationHelper.shouldRequestBatteryOptimization(this)) {
            BatteryOptimizationHelper.requestBatteryOptimizationExemption(this)
        }

        // Start listening for incoming call invitations
        CallSignalingManager.startListeningForCalls(this) { invitation ->
            Log.d("HomeActivity", "📞 Received call from: ${invitation.fromUserName}")
            
            // Launch incoming call activity
            val intent = Intent(this@HomeActivity, IncomingCallActivity::class.java).apply {
                putExtra("invitationId", invitation.id)
                putExtra("fromUserName", invitation.fromUserName)
                putExtra("fromUserId", invitation.fromUserId)
                putExtra("roomName", invitation.roomName)
                putExtra("url", invitation.url)
                putExtra("token", invitation.token)
                putExtra("callerPhotoUrl", invitation.avatarUrl)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            startActivity(intent)
        }

        setContent {
            HomeScreen()
        }

        loadContacts()
        loadRecentCalls()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Stop listening for calls when activity is destroyed
        CallSignalingManager.stopListeningForCalls()
    }

    @Composable
    fun HomeScreen() {
        var search by remember { mutableStateOf("") }
        var showProfileMenu by remember { mutableStateOf(false) }
        var currentView by remember { mutableStateOf("contacts") }
        
        val currentUser = auth.currentUser
        val userName = currentUser?.displayName ?: currentUser?.email?.substringBefore("@") ?: "User"
        val welcomeMessage = "Welcome, $userName"

        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.BackgroundDark)
                .windowInsetsPadding(WindowInsets.systemBars)
        ) {
            // Top bar with logo and profile button
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp)
            ) {
                // Logo (top left corner with offset)
                Image(
                    painter = painterResource(id = R.drawable.newlogo3),
                    contentDescription = "Tres3 Logo",
                    modifier = Modifier
                        .size(120.dp)
                        .offset(x = (-22).dp, y = (-34).dp)
                        .align(Alignment.TopStart)
                )
                
                // Profile button (top right corner - aligned with logo)
                Box(modifier = Modifier.align(Alignment.TopEnd)) {
                    Box(
                        modifier = Modifier
                            .size(43.dp)
                            .clip(CircleShape)
                            .background(AppColors.Gray.copy(alpha = 0.2f))
                            .clickable { showProfileMenu = true },
                        contentAlignment = Alignment.Center
                    ) {
                        val profilePhotoUrl = currentUser?.photoUrl
                        if (profilePhotoUrl != null) {
                            AsyncImage(
                                model = profilePhotoUrl,
                                contentDescription = "Profile Picture",
                                modifier = Modifier
                                    .size(43.dp)
                                    .clip(CircleShape),
                                contentScale = ContentScale.Crop
                            )
                        } else {
                            val initials = userName.take(2).uppercase()
                            Text(
                                text = initials,
                                color = AppColors.TextLight,
                                fontWeight = FontWeight.Bold,
                                fontSize = 18.sp
                            )
                        }
                    }
                    
                    // Dropdown menu
                    DropdownMenu(
                        expanded = showProfileMenu,
                        onDismissRequest = { showProfileMenu = false },
                        modifier = Modifier
                            .clip(RoundedCornerShape(12.dp)) // Clip first to remove white corners
                            .background(
                                AppColors.BackgroundDark.copy(alpha = 0.85f), // Background color with transparency
                                shape = RoundedCornerShape(12.dp)
                            )
                    ) {
                        DropdownMenuItem(
                            text = { Text("Profile", color = Color.White) },
                            onClick = {
                                showProfileMenu = false
                                try {
                                    Log.d("HomeActivity", "Opening ProfileActivity")
                                    val intent = Intent(this@HomeActivity, ProfileActivity::class.java)
                                    startActivity(intent)
                                } catch (e: android.content.ActivityNotFoundException) {
                                    Log.e("HomeActivity", "ProfileActivity not found in manifest", e)
                                    Toast.makeText(this@HomeActivity, "Profile page not configured", Toast.LENGTH_SHORT).show()
                                } catch (e: Exception) {
                                    e.printStackTrace()
                                    Log.e("HomeActivity", "Error opening profile", e)
                                    Toast.makeText(this@HomeActivity, "Error: ${e.message}", Toast.LENGTH_SHORT).show()
                                }
                            },
                            leadingIcon = {
                                Icon(Icons.Default.Person, contentDescription = null, tint = Color.White)
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Settings", color = Color.White) },
                            onClick = {
                                showProfileMenu = false
                                startActivity(Intent(this@HomeActivity, SettingsActivity::class.java))
                            },
                            leadingIcon = {
                                Icon(Icons.Default.Settings, contentDescription = null, tint = Color.White)
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Sign Out", color = Color.Red) },
                            onClick = {
                                showProfileMenu = false
                                auth.currentUser?.uid?.let { userId ->
                                    firestore.collection("users")
                                        .document(userId)
                                        .update("isOnline", false)
                                }
                                auth.signOut()
                                startActivity(Intent(this@HomeActivity, SignInActivity::class.java))
                                finish()
                            },
                            leadingIcon = {
                                Icon(Icons.AutoMirrored.Filled.ExitToApp, contentDescription = null, tint = Color.Red)
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Crash Reports", color = Color.Yellow) },
                            onClick = {
                                showProfileMenu = false
                                startActivity(Intent(this@HomeActivity, CrashReportActivity::class.java))
                            },
                            leadingIcon = {
                                Icon(Icons.Default.Warning, contentDescription = null, tint = Color.Yellow)
                            }
                        )
                    }
                }
            }

            // Main content
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 24.dp)
                    .padding(top = 20.dp), // Added top padding to move welcome up
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Welcome message
                MaterializeText(
                    text = welcomeMessage,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White,
                    modifier = Modifier.padding(bottom = 16.dp) // Reduced from 34dp
                )

                // Animated placeholder text
                val placeholderWords = listOf("Email", "Display name", "Phone")
                var currentWordIndex by remember { mutableStateOf(0) }
                
                LaunchedEffect(Unit) {
                    while (true) {
                        delay(2000)
                        currentWordIndex = (currentWordIndex + 1) % placeholderWords.size
                    }
                }

                // Search input
                var showAddContactDialog by remember { mutableStateOf(false) }
                
                OutlinedTextField(
                    value = search,
                    onValueChange = { search = it },
                    placeholder = { 
                        Row {
                            Text("Search ")
                            AnimatedTickerText(text = placeholderWords[currentWordIndex])
                        }
                    },
                    leadingIcon = { Text("@", color = AppColors.TextLight, fontSize = 18.sp) },
                    trailingIcon = {
                        IconButton(onClick = { showAddContactDialog = true }) {
                            Icon(
                                Icons.Default.PersonAdd,
                                contentDescription = "Add Contact",
                                tint = AppColors.PrimaryBlue
                            )
                        }
                    },
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
                
                // Add Contact Dialog
                if (showAddContactDialog) {
                    AddContactDialog(
                        onDismiss = { showAddContactDialog = false },
                        onAddContact = { email ->
                            // The contact will be automatically loaded from Firestore
                            loadContacts()
                            showAddContactDialog = false
                        }
                    )
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Action buttons row
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Button(
                        onClick = { currentView = "contacts" },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (currentView == "contacts") AppColors.PrimaryBlue else AppColors.Gray.copy(alpha = 0.3f)
                        ),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.Person, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Contacts")
                    }

                    Button(
                        onClick = { currentView = "history" },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (currentView == "history") AppColors.PrimaryBlue else AppColors.Gray.copy(alpha = 0.3f)
                        ),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.DateRange, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("History")
                    }
                }

                Spacer(modifier = Modifier.height(32.dp))

                Text(
                    if (currentView == "contacts") "Your Contacts" else "Call History",
                    style = MaterialTheme.typography.headlineSmall,
                    color = AppColors.TextLight,
                    modifier = Modifier.align(Alignment.Start)
                )

                Spacer(modifier = Modifier.height(16.dp))

                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    if (currentView == "contacts") {
                        val filteredContacts = contacts.filter { contact ->
                            search.isEmpty() ||
                            contact.name.contains(search, ignoreCase = true) ||
                            contact.email.contains(search, ignoreCase = true)
                        }
                        items(filteredContacts) { contact ->
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp)
                                    .clickable {
                                        initiateCall(contact)
                                    },
                                colors = CardDefaults.cardColors(containerColor = AppColors.Gray.copy(alpha = 0.1f))
                            ) {
                                Row(
                                    modifier = Modifier.padding(16.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(40.dp)
                                            .clip(CircleShape)
                                            .background(AppColors.PrimaryBlue),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(
                                            text = contact.name.firstOrNull()?.toString() ?: "?",
                                            color = Color.White,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }

                                    Spacer(modifier = Modifier.width(16.dp))

                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(contact.name, color = AppColors.TextLight, fontWeight = FontWeight.Medium)
                                        Text(contact.email, color = AppColors.TextLight.copy(alpha = 0.7f))
                                    }

                                    IconButton(onClick = { 
                                        initiateCall(contact)
                                    }) {
                                        Icon(
                                            painter = painterResource(id = R.drawable.ic_call_end),
                                            contentDescription = "Call",
                                            tint = AppColors.PrimaryBlue
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        items(recentCalls) { call ->
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp),
                                colors = CardDefaults.cardColors(containerColor = AppColors.Gray.copy(alpha = 0.1f))
                            ) {
                                Row(
                                    modifier = Modifier.padding(16.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(
                                        painter = painterResource(id = R.drawable.ic_call_end),
                                        contentDescription = "Call",
                                        tint = when (call.callStatus) {
                                            com.example.tres3.data.CallStatus.MISSED -> Color.Red
                                            com.example.tres3.data.CallStatus.REJECTED -> Color.Yellow
                                            else -> AppColors.PrimaryBlue
                                        },
                                        modifier = Modifier.size(24.dp)
                                    )

                                    Spacer(modifier = Modifier.width(16.dp))

                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = if (call.callerId == auth.currentUser?.uid) "To: ${call.receiverName}" else "From: ${call.callerName}",
                                            color = AppColors.TextLight,
                                            fontWeight = FontWeight.Medium
                                        )
                                        Text(
                                            text = "${call.callType} • ${formatDuration(call.duration)}",
                                            color = AppColors.TextLight.copy(alpha = 0.7f)
                                        )
                                    }

                                    Text(
                                        text = formatTimestamp(call.timestamp),
                                        color = AppColors.TextLight.copy(alpha = 0.7f),
                                        fontSize = 12.sp
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun initiateCall(contact: Contact) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingContact = contact
            permissionLauncher.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
            return
        }
        
        initiateCallAfterPermissions(contact)
    }

    private fun initiateCallAfterPermissions(contact: Contact) {
        if (isCallSetupInProgress) {
            Toast.makeText(this, "Call is already being set up", Toast.LENGTH_SHORT).show()
            return
        }

        try {
            Log.d("HomeActivity", "Initiating call to: ${contact.name}, ID: ${contact.id}")

            val currentUser = auth.currentUser
            if (currentUser == null) {
                Toast.makeText(this, "Not authenticated. Please sign in again.", Toast.LENGTH_LONG).show()
                startActivity(Intent(this, SignInActivity::class.java))
                finish()
                return
            }

            Log.d("HomeActivity", "User authenticated: ${currentUser.uid}")

            isCallSetupInProgress = true

            lifecycleScope.launch {
                try {
                    // Ensure any previous room instance is fully cleaned up before starting a new call
                    LiveKitManager.disconnectFromRoom()

                    // Fetch token for the caller (current user)
                    // Note: calleeId is only used for room name construction
                    val tokenData = getTokenForCall(contact.id)
                    Log.d("HomeActivity", "Token data received: $tokenData")

                    val token = tokenData["token"] as? String
                    val url = tokenData["url"] as? String

                    if (url.isNullOrEmpty() || token.isNullOrEmpty()) {
                        throw Exception("Token or URL missing from response")
                    }

                    // Get token for the recipient (callee)
                    val recipientTokenData = getTokenForCall(contact.id)
                    val recipientToken = recipientTokenData["token"] as? String ?: ""
                    
                    val roomName = "call-${currentUser.uid}-${contact.id}"
                    
                    // Fetch caller's avatar URL from Firestore
                    val callerAvatarUrl = try {
                        val userDoc = FirebaseFirestore.getInstance()
                            .collection("users")
                            .document(currentUser.uid)
                            .get()
                            .await()
                        userDoc.getString("avatarUrl")
                    } catch (e: Exception) {
                        Log.e("HomeActivity", "Failed to fetch caller avatar: ${e.message}")
                        null
                    }
                    
                    // Send call invitation asynchronously (don't wait for completion)
                    lifecycleScope.launch(Dispatchers.IO) {
                        try {
                            CallSignalingManager.sendCallInvitation(
                                recipientUserId = contact.id,
                                recipientName = contact.name,
                                roomName = roomName,
                                roomUrl = url,
                                token = recipientToken,
                                callerAvatarUrl = callerAvatarUrl
                            )
                            Log.d("HomeActivity", "✅ Call invitation sent")
                        } catch (e: Exception) {
                            Log.e("HomeActivity", "Failed to send invitation: ${e.message}")
                        }
                    }

                    // Skip native UI for now - go directly to InCallActivity
                    Log.d("HomeActivity", "🔄 Starting call with direct connection")
                    
                    try {
                        // Connect to room first
                        val room = LiveKitManager.connectToRoom(this@HomeActivity, url, token)
                        
                        withContext(Dispatchers.Main) {
                            room.localParticipant.setCameraEnabled(true)
                            room.localParticipant.setMicrophoneEnabled(true)
                        }

                        // Then start InCallActivity
                        val intent = Intent(this@HomeActivity, InCallActivity::class.java).apply {
                            putExtra("recipient_name", contact.name)
                            putExtra("contact_id", contact.id)
                            putExtra("recipient_email", contact.email)
                        }
                        
                        withContext(Dispatchers.Main) {
                            startActivity(intent)
                        }
                        
                        Log.d("HomeActivity", "✅ Call started successfully")
                        
                    } catch (e: Exception) {
                        Log.e("HomeActivity", "❌ Failed to connect to room", e)
                        withContext(Dispatchers.Main) {
                            Toast.makeText(
                                this@HomeActivity,
                                "Failed to connect: ${e.message}",
                                Toast.LENGTH_LONG
                            ).show()
                        }
                        // Don't rethrow; keep the app alive
                        return@launch
                    }

                } catch (e: Exception) {
                    Log.e("HomeActivity", "Error in call setup", e)
                    e.printStackTrace()
                    runOnUiThread {
                        Toast.makeText(
                            this@HomeActivity,
                            "Failed to start call: ${e.message}",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                    try {
                        LiveKitManager.disconnectFromRoom()
                    } catch (_: Exception) {
                        // Ignore cleanup exceptions
                    }
                } finally {
                    isCallSetupInProgress = false
                }
            }

        } catch (e: Exception) {
            e.printStackTrace()
            Log.e("HomeActivity", "Error starting call", e)
            isCallSetupInProgress = false
            Toast.makeText(this, "Error starting call: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }
    
    private fun registerFCMToken() {
        lifecycleScope.launch {
            try {
                val currentUser = auth.currentUser ?: return@launch
                
                // Get FCM token
                FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                    if (!task.isSuccessful) {
                        Log.w("HomeActivity", "❌ Failed to get FCM token", task.exception)
                        return@addOnCompleteListener
                    }
                    
                    val token = task.result
                    Log.d("HomeActivity", "📱 FCM Token: ${token.take(20)}...")
                    
                    // Save to Firestore
                    lifecycleScope.launch {
                        try {
                            firestore.collection("users")
                                .document(currentUser.uid)
                                .set(hashMapOf("fcmToken" to token), SetOptions.merge())
                                .await()
                            
                            Log.d("HomeActivity", "✅ FCM token saved to Firestore")
                        } catch (e: Exception) {
                            Log.e("HomeActivity", "❌ Failed to save FCM token", e)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("HomeActivity", "❌ Error registering FCM token", e)
            }
        }
    }
    
    private suspend fun getTokenForCall(calleeId: String): Map<String, Any> {
        val currentUser = auth.currentUser
            ?: throw Exception("Not authenticated")
        
        Log.d("HomeActivity", "Current user: ${currentUser.uid}")
        Log.d("HomeActivity", "User email: ${currentUser.email}")
        Log.d("HomeActivity", "User isAnonymous: ${currentUser.isAnonymous}")
        
        // Force refresh the ID token to ensure it's valid
        val tokenResult = currentUser.getIdToken(true).await()
        val idToken = tokenResult.token
        Log.d("HomeActivity", "Got ID token: ${idToken?.take(20)}...")
        Log.d("HomeActivity", "Token expiration: ${tokenResult.expirationTimestamp}")
        
        if (idToken == null) {
            throw Exception("Failed to get ID token")
        }
        
        // Use us-central1 region where functions are deployed
        val functions = FirebaseFunctions.getInstance("us-central1")
        
        Log.d("HomeActivity", "Firebase Functions instance created for us-central1")
        Log.d("HomeActivity", "Firebase App name: ${FirebaseApp.getInstance().name}")
        Log.d("HomeActivity", "Firebase Auth current user still valid: ${auth.currentUser != null}")
        
        val data = hashMapOf(
            "calleeId" to calleeId,
            "roomName" to "call-${currentUser.uid}-${calleeId}"
        )
        
        return try {
            Log.d("HomeActivity", "Calling Firebase Function...")
            
            val result = functions
                .getHttpsCallable("getLiveKitToken")
                .call(data)
                .await()
            
            Log.d("HomeActivity", "Firebase Function SUCCESS")
            Log.d("HomeActivity", "Raw result.data type: ${result.data?.javaClass?.name}")
            Log.d("HomeActivity", "Raw result.data content: ${result.data}")
            
            @Suppress("UNCHECKED_CAST")
            val response = when (val resultData = result.data) {
                is Map<*, *> -> resultData as Map<String, Any>
                else -> {
                    Log.e("HomeActivity", "Unexpected response type: ${resultData?.javaClass?.name}")
                    throw Exception("Invalid response format from server")
                }
            }
            
            if (!response.containsKey("token") || !response.containsKey("url")) {
                Log.e("HomeActivity", "Missing token or URL in response: $response")
                throw Exception("Server response missing token or URL")
            }
            
            Log.d("HomeActivity", "Token: ${(response["token"] as? String)?.take(50)}...")
            Log.d("HomeActivity", "URL: ${response["url"]}")
            
            response
        } catch (e: com.google.firebase.functions.FirebaseFunctionsException) {
            Log.e("HomeActivity", "Firebase Function ERROR: ${e.message}")
            Log.e("HomeActivity", "Error code: ${e.code}")
            Log.e("HomeActivity", "Error details: ${e.details}")
            throw e
        } catch (e: Exception) {
            Log.e("HomeActivity", "General ERROR: ${e.message}", e)
            e.printStackTrace()
            throw e
        }
    }

    private fun loadContacts() {
        val currentUserId = auth.currentUser?.uid ?: return
        val currentUserEmail = auth.currentUser?.email?.lowercase()
        
        Log.d("HomeActivity", "🔍 Loading contacts, filtering out current user ID: $currentUserId, email: $currentUserEmail")
        
        firestore.collection("users")
            .get()
            .addOnSuccessListener { documents ->
                contacts.clear()
                
                // Use maps to track unique users by both ID and email to prevent ANY duplicates
                val addedUserIds = mutableSetOf<String>()
                val addedEmails = mutableSetOf<String>()
                
                Log.d("HomeActivity", "📋 Total documents in users collection: ${documents.size()}")
                
                for (document in documents) {
                    val docId = document.id
                    val firestoreEmail = document.getString("email")?.lowercase()
                    
                    Log.d("HomeActivity", "📄 Processing document: ID=$docId, email=$firestoreEmail")
                    
                    // Skip current user by ID
                    if (docId == currentUserId) {
                        Log.d("HomeActivity", "⏭️ Skipping current user by ID: $docId")
                        continue
                    }
                    
                    // Skip current user by email (case-insensitive)
                    if (firestoreEmail != null && firestoreEmail == currentUserEmail) {
                        Log.d("HomeActivity", "⏭️ Skipping current user by email: $firestoreEmail")
                        continue
                    }
                    
                    // Skip if we've already added this user ID (prevents duplicates)
                    if (addedUserIds.contains(docId)) {
                        Log.d("HomeActivity", "⏭️ Skipping duplicate user ID: $docId")
                        continue
                    }
                    
                    // Skip if we've already added this email (prevents email duplicates)
                    if (firestoreEmail != null && addedEmails.contains(firestoreEmail)) {
                        Log.d("HomeActivity", "⏭️ Skipping duplicate email: $firestoreEmail (already added)")
                        continue
                    }
                    
                    // Skip if no email at all (invalid user record)
                    if (firestoreEmail == null || firestoreEmail.isEmpty()) {
                        Log.d("HomeActivity", "⏭️ Skipping user with no email: $docId")
                        continue
                    }
                    
                    // Prioritize display name from Firestore, fallback to email prefix
                    val firestoreDisplayName = document.getString("displayName")

                    val displayName = firestoreDisplayName
                        ?: firestoreEmail.substringBefore("@")

                    val contact = Contact(
                        id = docId,
                        name = displayName,
                        email = firestoreEmail,
                        avatarUrl = document.getString("avatarUrl"),
                        isOnline = document.getBoolean("isOnline") ?: false
                    )
                    contacts.add(contact)
                    addedUserIds.add(docId)
                    addedEmails.add(firestoreEmail)
                    
                    Log.d("HomeActivity", "✅ Added contact: ${contact.name} (ID: ${contact.id}) - email: ${contact.email}")
                }
                Log.d("HomeActivity", "✅ Total contacts loaded: ${contacts.size}")
            }.addOnFailureListener { exception ->
                Log.e("HomeActivity", "❌ Error loading contacts", exception)
                exception.printStackTrace()
            }
    }

    private fun formatDuration(seconds: Long): String {
        val minutes = seconds / 60
        val remainingSeconds = seconds % 60
        return if (minutes > 0) {
            "${minutes}m ${remainingSeconds}s"
        } else {
            "${remainingSeconds}s"
        }
    }

    private fun formatTimestamp(timestamp: Date?): String {
        if (timestamp == null) return ""
        val now = Date()
        val diff = now.time - timestamp.time
        val minutes = diff / (1000 * 60)
        val hours = diff / (1000 * 60 * 60)
        val days = diff / (1000 * 60 * 60 * 24)

        return when {
            minutes < 1 -> "Just now"
            minutes < 60 -> "${minutes}m ago"
            hours < 24 -> "${hours}h ago"
            else -> "${days}d ago"
        }
    }

    private fun loadRecentCalls() {
        callHistoryRepository.getCallHistory { calls ->
            recentCalls.clear()
            recentCalls.addAll(calls)
        }
    }
}

@Composable
fun AddContactDialog(
    onDismiss: () -> Unit,
    onAddContact: (String) -> Unit
) {
    var email by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                "Add Contact",
                color = AppColors.TextLight,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )
        },
        text = {
            Column {
                Text(
                    "Enter the email or phone number of the person you want to add",
                    color = AppColors.TextLight.copy(alpha = 0.7f),
                    fontSize = 14.sp
                )
                
                Spacer(modifier = Modifier.height(16.dp))
                
                OutlinedTextField(
                    value = email,
                    onValueChange = { 
                        email = it
                        errorMessage = ""
                    },
                    label = { Text("Email or phone number") },
                    placeholder = { Text("user@example.com") },
                    leadingIcon = { 
                        Icon(Icons.Default.Person, contentDescription = null, tint = AppColors.TextLight) 
                    },
                    singleLine = true,
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
                
                if (errorMessage.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        errorMessage,
                        color = Color.Red,
                        fontSize = 12.sp
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    if (email.isBlank()) {
                        errorMessage = "Please enter an email or phone number"
                        return@Button
                    }
                    
                    isLoading = true
                    errorMessage = ""
                    
                    // Search for user in Firestore by email
                    FirebaseFirestore.getInstance()
                        .collection("users")
                        .whereEqualTo("email", email.trim())
                        .get()
                        .addOnSuccessListener { documents ->
                            isLoading = false
                            if (documents.isEmpty) {
                                errorMessage = "User not found"
                            } else {
                                // User found, contact will be loaded automatically
                                onAddContact(email.trim())
                            }
                        }
                        .addOnFailureListener { e ->
                            isLoading = false
                            errorMessage = "Error: ${e.message}"
                        }
                },
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryBlue),
                enabled = !isLoading
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text("Add")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = AppColors.TextLight)
            }
        },
        containerColor = AppColors.BackgroundDark,
        tonalElevation = 8.dp
    )
}