package com.example.tres3

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
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
    val isOnline: Boolean = false,
    val status: com.example.tres3.presence.UserStatus = com.example.tres3.presence.UserStatus.OFFLINE,
    val lastSeen: java.util.Date? = null,
    val isPinned: Boolean = false
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
    
    // Guest link dialog state
    private var showGuestLinkDialog by mutableStateOf(false)
    private var generatedGuestLink by mutableStateOf("")
    private var guestLinkLoading by mutableStateOf(false)
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
        
        // Request full-screen intent permission on Android 14+ (U and above)
        // This is REQUIRED for showing incoming call UI when app is closed
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            if (!notificationManager.canUseFullScreenIntent()) {
                Log.w("HomeActivity", "⚠️ Full-screen intent permission not granted")
                // Open settings to grant permission
                try {
                    val intent = Intent(android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    Log.e("HomeActivity", "Failed to open full-screen intent settings", e)
                }
            } else {
                Log.d("HomeActivity", "✅ Full-screen intent permission already granted")
            }
        }

        // Register FCM token for push notifications
        registerFCMToken()
        
        // Initialize user presence tracking
        com.example.tres3.presence.UserPresenceManager.initialize(this)

        // Request battery optimization exemption if needed
        if (BatteryOptimizationHelper.shouldRequestBatteryOptimization(this)) {
            BatteryOptimizationHelper.requestBatteryOptimizationExemption(this)
        }

        // Prepare LiveData to surface incoming-call banner in Compose when app is foregrounded
    // Bridge for in-app banner without adding LiveData-Compose dependency
    var setIncomingInvite: ((CallInvitation?) -> Unit)? = null

        // Start listening for incoming call invitations
        CallSignalingManager.startListeningForCalls(this) { invitation ->
            Log.d("HomeActivity", "📞 Received call from: ${invitation.fromUserName}")
            // If activity is in foreground, show in-app banner; otherwise, fall back to full-screen activity
            val isFg = lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)
            if (isFg) {
                runOnUiThread { setIncomingInvite?.invoke(invitation) }
            } else {
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
        }

        setContent {
            val inviteState = remember { mutableStateOf<CallInvitation?>(null) }
            // Expose setter to Activity scope so listener can update UI
            DisposableEffect(Unit) {
                setIncomingInvite = { invite -> inviteState.value = invite }
                onDispose { setIncomingInvite = null }
            }
            HomeScreen(inviteState)
        }

        loadContacts()
        loadRecentCalls()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Stop listening for calls when activity is destroyed
        CallSignalingManager.stopListeningForCalls()
        // Cleanup presence manager
        com.example.tres3.presence.UserPresenceManager.cleanup()
    }

    @Composable
    fun HomeScreen(inviteState: androidx.compose.runtime.MutableState<CallInvitation?>) {
        var search by remember { mutableStateOf("") }
        var showProfileMenu by remember { mutableStateOf(false) }
        var currentView by remember { mutableStateOf("contacts") }
        
        val currentUser = auth.currentUser
        // Get user's name and photo from Firestore first, then fallback to Auth data
        var userDisplayName by remember { mutableStateOf<String?>(null) }
        var userProfilePhotoUrl by remember { mutableStateOf<String?>(null) }
        
        LaunchedEffect(currentUser?.uid) {
            currentUser?.uid?.let { uid ->
                try {
                    val userDoc = firestore.collection("users").document(uid).get().await()
                    userDisplayName = userDoc.getString("name") ?: userDoc.getString("displayName")
                    userProfilePhotoUrl = userDoc.getString("photoUrl")
                } catch (e: Exception) {
                    Log.e("HomeActivity", "Error fetching user data", e)
                }
            }
        }
        
        val userName = userDisplayName 
            ?: currentUser?.displayName 
            ?: currentUser?.email?.substringBefore("@") 
            ?: "User"
        val profilePhotoUrl = userProfilePhotoUrl ?: currentUser?.photoUrl
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
                            .background(Color.Transparent) // Remove default white background
                            .clip(RoundedCornerShape(12.dp)),
                        containerColor = AppColors.BackgroundDark.copy(alpha = 0.95f), // Use containerColor instead
                        shape = RoundedCornerShape(12.dp)
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
                            text = { Text("Create Guest Link", color = Color.White) },
                            onClick = {
                                showProfileMenu = false
                                showGuestLinkDialog = true
                            },
                            leadingIcon = {
                                Icon(Icons.Default.Share, contentDescription = null, tint = Color.White)
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
                                val current = auth.currentUser
                                current?.uid?.let { userId ->
                                    // Mark offline and remove this device's FCM token to avoid stale calls on account switch
                                    lifecycleScope.launch {
                                        try {
                                            val userRef = firestore.collection("users").document(userId)
                                            userRef.update(mapOf(
                                                "isOnline" to false,
                                                "fcmToken" to com.google.firebase.firestore.FieldValue.delete()
                                            ))
                                            Log.d("HomeActivity", "✅ Cleared FCM token for user $userId on sign-out")
                                        } catch (e: Exception) {
                                            Log.w("HomeActivity", "⚠️ Failed to clear FCM token at sign-out: ${e.message}")
                                        }
                                    }
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
                val placeholderWords = listOf("Email", "Phone", "Username")
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

                // Guest Link Dialog
                if (showGuestLinkDialog) {
                    GuestLinkDialog(
                        onDismiss = { 
                            showGuestLinkDialog = false
                            generatedGuestLink = ""
                            guestLinkLoading = false
                        },
                        generatedLink = generatedGuestLink,
                        isLoading = guestLinkLoading,
                        onGenerateLink = { guestName ->
                            generateGuestLink(guestName)
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
                        val filteredContacts = contacts
                            .filter { contact ->
                                search.isEmpty() ||
                                contact.name.contains(search, ignoreCase = true) ||
                                contact.email.contains(search, ignoreCase = true)
                            }
                            .sortedWith(compareByDescending<Contact> { it.isPinned }.thenBy { it.name })
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
                                        modifier = Modifier.size(40.dp)
                                    ) {
                                        // Avatar
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
                                        
                                        // Presence indicator
                                        if (contact.isOnline) {
                                            Box(
                                                modifier = Modifier
                                                    .size(12.dp)
                                                    .align(Alignment.BottomEnd)
                                                    .clip(CircleShape)
                                                    .background(
                                                        when (contact.status) {
                                                            com.example.tres3.presence.UserStatus.ONLINE -> Color(0xFF00C853) // Green
                                                            com.example.tres3.presence.UserStatus.BUSY -> Color(0xFFFF1744) // Red
                                                            com.example.tres3.presence.UserStatus.AWAY -> Color(0xFFFFC107) // Amber
                                                            com.example.tres3.presence.UserStatus.OFFLINE -> Color(0xFF757575) // Gray
                                                        }
                                                    )
                                                    .border(2.dp, AppColors.BackgroundDark, CircleShape)
                                            )
                                        }
                                    }

                                    Spacer(modifier = Modifier.width(16.dp))

                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(contact.name, color = AppColors.TextLight, fontWeight = FontWeight.Medium)
                                        Text(contact.email, color = AppColors.TextLight.copy(alpha = 0.7f))
                                    }

                                    // Pin/Favorite button
                                    IconButton(onClick = { 
                                        toggleContactPin(contact.id, !contact.isPinned)
                                        // Update local state
                                        val index = contacts.indexOfFirst { it.id == contact.id }
                                        if (index != -1) {
                                            contacts[index] = contact.copy(isPinned = !contact.isPinned)
                                        }
                                    }) {
                                        Icon(
                                            imageVector = if (contact.isPinned) Icons.Default.Star else Icons.Default.StarBorder,
                                            contentDescription = if (contact.isPinned) "Unpin" else "Pin",
                                            tint = if (contact.isPinned) Color(0xFFFFC107) else AppColors.TextLight.copy(alpha = 0.5f)
                                        )
                                    }

                                    // Call button
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
        // Observe incoming invitation to show a sleek top banner
    val invite = inviteState.value

    Box(Modifier.fillMaxSize()) {
            // Existing Home UI
            Column(Modifier.fillMaxSize()) {
                // ... existing Home UI content follows (contacts/recent etc.)
            }

            // Incoming call banner
            androidx.compose.animation.AnimatedVisibility(
                visible = invite != null,
                enter = androidx.compose.animation.slideInVertically { full -> -full } + androidx.compose.animation.fadeIn(),
                exit = androidx.compose.animation.slideOutVertically { full -> -full } + androidx.compose.animation.fadeOut(),
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .windowInsetsPadding(WindowInsets.statusBars)
            ) {
                invite?.let { inv ->
                    Surface(
                        modifier = Modifier
                            .padding(top = 12.dp)
                            .fillMaxWidth(0.96f)
                            .heightIn(min = 88.dp)
                            .clip(RoundedCornerShape(16.dp))
                            ,
                        color = Color(0xCC111214) /* semi-translucent */,
                        tonalElevation = 8.dp,
                        shadowElevation = 8.dp
                    ) {
                        Row(
                            modifier = Modifier
                                .background(Color(0xCC111214))
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(44.dp)
                                        .clip(CircleShape)
                                        .background(Color(0x22FFFFFF)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    val initial = (inv.fromUserName.takeIf { it.isNotBlank() } ?: "?")
                                    Text(text = initial.substring(0,1).uppercase(), color = Color.White, fontWeight = FontWeight.Bold)
                                }
                                Spacer(Modifier.width(12.dp))
                                Column {
                                    Text(text = inv.fromUserName, color = Color.White, fontWeight = FontWeight.SemiBold)
                                    Text(text = "Incoming call", color = Color.White.copy(alpha = 0.75f), fontSize = 12.sp)
                                }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                // Decline
                                TextButton(
                                    onClick = {
                                        lifecycleScope.launch {
                                            try { CallSignalingManager.rejectCallInvitation(inv.id) } catch (_: Exception) {}
                                            inviteState.value = null
                                        }
                                    },
                                    colors = ButtonDefaults.textButtonColors(contentColor = Color(0xFFFF6B6B))
                                ) { Text("Decline") }

                                // Accept
                                Button(
                                    onClick = {
                                        lifecycleScope.launch {
                                            try {
                                                val room = LiveKitManager.connectToRoom(this@HomeActivity, inv.url, inv.token)
                                                withContext(Dispatchers.Main) {
                                                    val intent = Intent(this@HomeActivity, InCallActivity::class.java).apply {
                                                        putExtra("recipient_name", inv.fromUserName)
                                                    }
                                                    startActivity(intent)
                                                }
                                            } catch (e: Exception) {
                                                Log.e("HomeActivity", "Failed to accept call: ${e.message}", e)
                                            } finally {
                                                inviteState.value = null
                                            }
                                        }
                                    },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2A84FF))
                                ) { Text("Accept", color = Color.White) }
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
            Log.d("HomeActivity", "📞 Initiating call to: ${contact.name}, ID: ${contact.id}")

            val currentUser = auth.currentUser
            if (currentUser == null) {
                Log.e("HomeActivity", "❌ Cannot initiate call: User not authenticated")
                Toast.makeText(this, "Not authenticated. Please sign in again.", Toast.LENGTH_LONG).show()
                startActivity(Intent(this, SignInActivity::class.java))
                finish()
                return
            }

            Log.d("HomeActivity", "✅ User authenticated: ${currentUser.uid}")

            isCallSetupInProgress = true

            lifecycleScope.launch {
                try {
                    // Check if recipient has FCM token (for diagnostics)
                    try {
                        val recipientDoc = FirebaseFirestore.getInstance()
                            .collection("users")
                            .document(contact.id)
                            .get()
                            .await()
                        
                        val recipientFcmToken = recipientDoc.getString("fcmToken")
                        if (recipientFcmToken.isNullOrEmpty()) {
                            Log.e("HomeActivity", "❌ Cannot call ${contact.name} - no FCM token registered")
                            
                            isCallSetupInProgress = false
                            
                            runOnUiThread {
                                androidx.appcompat.app.AlertDialog.Builder(this@HomeActivity)
                                    .setTitle("Cannot Place Call")
                                    .setMessage("${contact.name} is not available to receive calls right now. They may need to:\n\n" +
                                            "• Open the app to register for notifications\n" +
                                            "• Check their internet connection\n" +
                                            "• Update their app to the latest version")
                                    .setPositiveButton("OK", null)
                                    .setNeutralButton("Retry") { _, _ ->
                                        // Give them option to try again (maybe token just registered)
                                        lifecycleScope.launch {
                                            kotlinx.coroutines.delay(1000) // Wait a second before retry
                                            initiateCall(contact)
                                        }
                                    }
                                    .show()
                            }
                            
                            return@launch  // STOP HERE - DO NOT PROCEED WITH CALL
                        }
                        
                        Log.d("HomeActivity", "✅ Recipient has FCM token (${recipientFcmToken.take(20)}...)")
                    } catch (e: Exception) {
                        Log.w("HomeActivity", "Could not check recipient FCM token: ${e.message}")
                    }
                    
                    // Ensure any previous room instance is fully cleaned up before starting a new call
                    LiveKitManager.disconnectFromRoom()

                    // Fetch token for the caller (current user) - ONLY ONCE
                    Log.d("HomeActivity", "🎫 Fetching LiveKit token for call...")
                    val tokenData = getTokenForCall(contact.id)
                    Log.d("HomeActivity", "✅ Token data received: ${tokenData.keys}")

                    val token = tokenData["token"] as? String
                    val url = tokenData["url"] as? String

                    if (url.isNullOrEmpty() || token.isNullOrEmpty()) {
                        throw Exception("Token or URL missing from response")
                    }

                    Log.d("HomeActivity", "🔗 WebSocket URL: $url")
                    Log.d("HomeActivity", "🎫 Token length: ${token.length}")

                    // Use the same token for recipient (they'll get their own via FCM)
                    val recipientToken = token // Reuse token instead of fetching again
                    
                    val roomName = "call-${currentUser.uid}-${contact.id}"

                    // Fetch caller's avatar URL and send invitation in parallel (don't block call)
                    lifecycleScope.launch(Dispatchers.IO) {
                        try {
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
                            
                            Log.d("HomeActivity", "📤 Sending call invitation via Firestore...")
                            CallSignalingManager.sendCallInvitation(
                                recipientUserId = contact.id,
                                recipientName = contact.name,
                                roomName = roomName,
                                roomUrl = url,
                                token = recipientToken,
                                callerAvatarUrl = callerAvatarUrl
                            )
                            Log.d("HomeActivity", "✅ Call invitation sent to Firestore")
                        } catch (e: Exception) {
                            Log.e("HomeActivity", "❌ Failed to send invitation: ${e.message}", e)
                        }
                    }

                    // Skip native UI for now - go directly to InCallActivity
                    Log.d("HomeActivity", "🔄 Starting call with direct connection")
                    
                    try {
                        // Connect to room first
                        Log.d("HomeActivity", "🔌 Connecting to LiveKit room...")
                        val room = LiveKitManager.connectToRoom(this@HomeActivity, url, token)
                        Log.d("HomeActivity", "✅ Connected to room: ${room.name}")
                        
                        withContext(Dispatchers.Main) {
                            Log.d("HomeActivity", "📹 Enabling camera and microphone...")
                            room.localParticipant.setCameraEnabled(true)
                            room.localParticipant.setMicrophoneEnabled(true)
                            Log.d("HomeActivity", "✅ Media enabled")
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
                        
                        Log.d("HomeActivity", "✅ Call started successfully - InCallActivity launched")
                        
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

    /**
     * Generate guest call link for non-app users
     */
    private fun generateGuestLink(guestName: String) {
        lifecycleScope.launch {
            try {
                guestLinkLoading = true
                
                val currentUser = auth.currentUser ?: throw Exception("Not authenticated")
                val roomName = "guest_${currentUser.uid}_${System.currentTimeMillis()}"
                
                Log.d("HomeActivity", "🔗 Generating NEW guest link for room: $roomName")
                
                // Call Firebase Function to generate guest token
                val functions = com.google.firebase.functions.FirebaseFunctions.getInstance()
                val data = hashMapOf(
                    "roomName" to roomName,
                    "guestName" to guestName
                )
                
                val result = functions
                    .getHttpsCallable("generateGuestToken")
                    .call(data)
                    .await()
                
                val responseData = result.data as Map<*, *>
                val link = responseData["link"] as? String 
                    ?: throw Exception("No link received from server")
                
                Log.d("HomeActivity", "✅ Generated FRESH guest link: $link")
                Log.d("HomeActivity", "📋 This is a NEW one-time-use link. Previous links will NOT work.")
                generatedGuestLink = link
                
                // Store the link for sharing - don't join yet!
                Log.d("HomeActivity", "📋 Link ready to share. Will join when guest opens it.")
                
            } catch (e: Exception) {
                Log.e("HomeActivity", "❌ Failed to generate guest link", e)
                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        this@HomeActivity, 
                        "Failed to generate link: ${e.message}", 
                        Toast.LENGTH_LONG
                    ).show()
                }
            } finally {
                guestLinkLoading = false
            }
        }
    }

    @Composable
    fun GuestLinkDialog(
        onDismiss: () -> Unit,
        generatedLink: String,
        isLoading: Boolean,
        onGenerateLink: (String) -> Unit
    ) {
        var guestName by remember { mutableStateOf("") }
        var lastGeneratedGuestName by remember { mutableStateOf("") }
        
        // Remember the guest name when link is generated
        LaunchedEffect(generatedLink) {
            if (generatedLink.isNotEmpty() && guestName.isNotBlank()) {
                lastGeneratedGuestName = guestName
            }
        }

        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Create Guest Call Link", color = AppColors.TextLight) },
            text = {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    if (generatedLink.isEmpty()) {
                        Text(
                            "Start a call with someone who doesn't have the app. You'll join the call first, then share the link with them.",
                            color = AppColors.TextLight.copy(alpha = 0.7f),
                            fontSize = 14.sp
                        )
                        
                        OutlinedTextField(
                            value = guestName,
                            onValueChange = { guestName = it },
                            label = { Text("Guest Name") },
                            placeholder = { Text("e.g., John Doe") },
                            singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = AppColors.PrimaryBlue,
                                unfocusedBorderColor = AppColors.Gray,
                                focusedLabelColor = AppColors.PrimaryBlue,
                                unfocusedLabelColor = AppColors.TextLight,
                                cursorColor = AppColors.PrimaryBlue,
                                focusedTextColor = AppColors.TextLight,
                                unfocusedTextColor = AppColors.TextLight
                            ),
                            modifier = Modifier.fillMaxWidth()
                        )
                    } else {
                        // WARNING: Single-use link notice
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Color(0xFFFFA726).copy(alpha = 0.2f), RoundedCornerShape(8.dp))
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.Start,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "⚠️ ONE-TIME USE ONLY - This link expires after the first person joins. Generate a new link for each call.",
                                color = AppColors.TextLight,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                        
                        Spacer(modifier = Modifier.height(8.dp))
                        
                        Text(
                            "Share this link:",
                            color = AppColors.TextLight,
                            fontWeight = FontWeight.Bold
                        )
                        
                        SelectionContainer {
                            Text(
                                generatedLink,
                                color = AppColors.PrimaryBlue,
                                fontSize = 12.sp,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(AppColors.Gray.copy(alpha = 0.2f), RoundedCornerShape(8.dp))
                                    .padding(12.dp)
                            )
                        }
                    }
                }
            },
            confirmButton = {
                if (generatedLink.isEmpty()) {
                    Button(
                        onClick = { 
                            if (guestName.isNotBlank()) {
                                onGenerateLink(guestName)
                            }
                        },
                        enabled = guestName.isNotBlank() && !isLoading,
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryBlue)
                    ) {
                        if (isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                color = Color.White
                            )
                        } else {
                            Text("Generate Link")
                        }
                    }
                } else {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // Share button
                        Button(
                            onClick = {
                                val shareIntent = Intent().apply {
                                    action = Intent.ACTION_SEND
                                    type = "text/plain"
                                    putExtra(Intent.EXTRA_TEXT, 
                                        "📞 Join my video call!\n\n$generatedLink\n\n✨ No app needed - just click to join from your browser!")
                                    putExtra(Intent.EXTRA_SUBJECT, "Video Call Invitation")
                                }
                                startActivity(Intent.createChooser(shareIntent, "Share guest link"))
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryBlue)
                        ) {
                            Icon(Icons.Default.Share, contentDescription = null)
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Share")
                        }
                        
                        // Copy button
                        Button(
                            onClick = {
                                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                                val clip = android.content.ClipData.newPlainText("Guest Link", generatedLink)
                                clipboard.setPrimaryClip(clip)
                                Toast.makeText(this@HomeActivity, "✅ Link copied to clipboard", Toast.LENGTH_SHORT).show()
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.Gray)
                        ) {
                            Icon(Icons.Default.ContentCopy, contentDescription = null)
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Copy")
                        }
                    }
                }
            },
            dismissButton = {
                if (generatedLink.isNotEmpty()) {
                    // If link exists, show "Generate New Link" button
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = onDismiss) {
                            Text("Close", color = AppColors.TextLight)
                        }
                        TextButton(
                            onClick = { 
                                // Regenerate with same guest name
                                if (lastGeneratedGuestName.isNotBlank()) {
                                    onGenerateLink(lastGeneratedGuestName)
                                }
                            },
                            enabled = !isLoading
                        ) {
                            if (isLoading) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    color = AppColors.PrimaryBlue
                                )
                            } else {
                                Icon(
                                    imageVector = Icons.Default.Refresh,
                                    contentDescription = null,
                                    tint = AppColors.PrimaryBlue,
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("New Link", color = AppColors.PrimaryBlue)
                        }
                    }
                } else {
                    TextButton(onClick = onDismiss) {
                        Text("Close", color = AppColors.TextLight)
                    }
                }
            },
            containerColor = AppColors.BackgroundDark
        )
    }

    /**
     * Generate and share a guest call link for non-app users
     */
    private fun shareGuestCallLink(contact: Contact) {
        lifecycleScope.launch {
            try {
                Toast.makeText(this@HomeActivity, "Generating guest link...", Toast.LENGTH_SHORT).show()
                
                val currentUser = auth.currentUser ?: throw Exception("Not authenticated")
                val roomName = "guest_call_${currentUser.uid}_${System.currentTimeMillis()}"
                
                // Call Firebase Function to generate guest token
                val functions = com.google.firebase.functions.FirebaseFunctions.getInstance()
                val data = hashMapOf(
                    "roomName" to roomName,
                    "guestName" to contact.name
                )
                
                val result = functions
                    .getHttpsCallable("generateGuestToken")
                    .call(data)
                    .await()
                
                val responseData = result.data as Map<*, *>
                val link = responseData["link"] as? String 
                    ?: throw Exception("No link received from server")
                
                Log.d("HomeActivity", "✅ Generated guest link: $link")
                generatedGuestLink = link
                
            } catch (e: Exception) {
                Log.e("HomeActivity", "❌ Failed to generate guest link", e)
                Toast.makeText(
                    this@HomeActivity, 
                    "Failed to generate link: ${e.message}", 
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    private fun registerFCMToken() {
        lifecycleScope.launch {
            try {
                val currentUser = auth.currentUser
                if (currentUser == null) {
                    Log.w("HomeActivity", "⚠️ Cannot register FCM token - user not authenticated")
                    return@launch
                }
                
                Log.d("HomeActivity", "🔄 Registering FCM token for user: ${currentUser.uid}")
                
                // Get FCM token with retry logic
                var attempts = 0
                val maxAttempts = 3
                
                while (attempts < maxAttempts) {
                    try {
                        val token = FirebaseMessaging.getInstance().token.await()
                        Log.d("HomeActivity", "📱 FCM Token obtained: ${token.take(20)}...")
                        
                        // Save to Firestore with merge
                        val userRef = firestore.collection("users").document(currentUser.uid)
                        
                        // Get current user's display name from Firebase Auth
                        val displayName = currentUser.displayName 
                            ?: currentUser.email?.substringBefore("@")
                            ?: "User"
                        val email = currentUser.email ?: ""
                        
                        // Always update the token and ensure displayName is set
                        userRef.set(
                            hashMapOf(
                                "fcmToken" to token,
                                "displayName" to displayName,
                                "email" to email,
                                "lastTokenUpdate" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                                "deviceInfo" to hashMapOf(
                                    "model" to android.os.Build.MODEL,
                                    "sdk" to android.os.Build.VERSION.SDK_INT
                                )
                            ),
                            SetOptions.merge()
                        ).await()
                        
                        Log.d("HomeActivity", "✅ FCM token successfully saved to Firestore")
                        
                        // Verify it was saved
                        val doc = userRef.get().await()
                        val savedToken = doc.getString("fcmToken")
                        if (savedToken == token) {
                            Log.d("HomeActivity", "✅ Verified: FCM token in Firestore matches")
                        } else {
                            Log.e("HomeActivity", "⚠️ WARNING: Saved token doesn't match! Expected: ${token.take(20)}, Got: ${savedToken?.take(20)}")
                        }
                        
                        // Clear any pending token
                        val prefs = getSharedPreferences("settings", Context.MODE_PRIVATE)
                        prefs.edit().remove("pending_fcm_token").apply()
                        
                        break // Success, exit retry loop
                        
                    } catch (e: Exception) {
                        attempts++
                        Log.e("HomeActivity", "❌ Attempt $attempts/$maxAttempts failed to register FCM token: ${e.message}", e)
                        if (attempts >= maxAttempts) {
                            Log.e("HomeActivity", "❌ Failed to register FCM token after $maxAttempts attempts")
                            // Save token locally for later retry
                            val prefs = getSharedPreferences("settings", Context.MODE_PRIVATE)
                            FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
                                prefs.edit().putString("pending_fcm_token", token).apply()
                                Log.d("HomeActivity", "💾 Saved FCM token locally for later retry")
                            }
                        } else {
                            delay(1000) // Wait 1 second before retry
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("HomeActivity", "❌ Critical error in registerFCMToken: ${e.message}", e)
            }
        }
    }
    
    private suspend fun getTokenForCall(calleeId: String): Map<String, Any> {
        val currentUser = auth.currentUser
            ?: throw Exception("Not authenticated")
        
        Log.d("HomeActivity", "Current user: ${currentUser.uid}")
        
        // Get ID token without forcing refresh (use cached token if valid)
        val tokenResult = currentUser.getIdToken(false).await()
        val idToken = tokenResult.token
        Log.d("HomeActivity", "Got ID token (cached): ${idToken?.take(20)}...")
        
        if (idToken == null) {
            throw Exception("Failed to get ID token")
        }
        
        // Use us-central1 region where functions are deployed
        val functions = FirebaseFunctions.getInstance("us-central1")
        
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

    private fun toggleContactPin(contactId: String, isPinned: Boolean) {
        val currentUserId = auth.currentUser?.uid ?: return
        
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                firestore.collection("users")
                    .document(currentUserId)
                    .collection("contacts")
                    .document(contactId)
                    .update("isPinned", isPinned)
                    .await()
                Log.d("HomeActivity", "⭐ Contact pinned status updated: $contactId -> $isPinned")
            } catch (e: Exception) {
                Log.e("HomeActivity", "❌ Failed to update pin status: ${e.message}", e)
            }
        }
    }

    private fun loadContacts() {
        val currentUserId = auth.currentUser?.uid ?: return
        
        Log.d("HomeActivity", "🔍 Loading contacts for user: $currentUserId")
        
        firestore.collection("users")
            .document(currentUserId)
            .collection("contacts")
            .get()
            .addOnSuccessListener { documents ->
                contacts.clear()
                
                Log.d("HomeActivity", "📋 Found ${documents.size()} contacts")
                
                for (document in documents) {
                    val displayName = document.getString("displayName")
                    val email = document.getString("email") ?: ""
                    val userId = document.getString("userId") ?: document.id
                    val isPinned = document.getBoolean("isPinned") ?: false
                    
                    val contact = Contact(
                        id = userId,
                        name = if (!displayName.isNullOrBlank()) displayName else email.ifEmpty { "Unknown" },
                        email = email,
                        avatarUrl = document.getString("photoUrl"),
                        isOnline = false, // Will be updated by presence fetch below
                        isPinned = isPinned
                    )
                    contacts.add(contact)
                    
                    // Fetch presence status asynchronously for each contact
                    lifecycleScope.launch {
                        try {
                            val status = com.example.tres3.presence.UserPresenceManager.getUserStatus(userId)
                            val isOnline = status == com.example.tres3.presence.UserStatus.ONLINE || 
                                          status == com.example.tres3.presence.UserStatus.BUSY
                            
                            // Update contact in list
                            val index = contacts.indexOfFirst { it.id == userId }
                            if (index != -1) {
                                contacts[index] = contact.copy(isOnline = isOnline, status = status)
                                Log.d("HomeActivity", "📡 ${contact.name} is ${status.name}")
                            }
                        } catch (e: Exception) {
                            Log.e("HomeActivity", "Failed to fetch presence for ${contact.name}: ${e.message}")
                        }
                    }
                    
                    Log.d("HomeActivity", "✅ Added contact: ${contact.name} (${contact.email})")
                }
                Log.d("HomeActivity", "✅ Total contacts loaded: ${contacts.size}")
            }.addOnFailureListener { exception ->
                Log.e("HomeActivity", "❌ Error loading contacts", exception)
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
                    label = { Text("Email or Phone") },
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
                    
                    val currentUser = FirebaseAuth.getInstance().currentUser
                    if (currentUser == null) {
                        errorMessage = "Not authenticated"
                        isLoading = false
                        return@Button
                    }
                    
                    // Search for user in Firestore by email (case-insensitive)
                    val searchEmail = email.trim().lowercase()
                    FirebaseFirestore.getInstance()
                        .collection("users")
                        .whereEqualTo("email", searchEmail)
                        .get()
                        .addOnSuccessListener { documents ->
                            if (documents.isEmpty) {
                                isLoading = false
                                errorMessage = "User not found"
                            } else {
                                val foundUser = documents.first()
                                val foundUserId = foundUser.id
                                val foundUserName = foundUser.getString("displayName") ?: email.trim()
                                val foundUserEmail = foundUser.getString("email") ?: email.trim()
                                val foundUserPhotoUrl = foundUser.getString("photoUrl")
                                
                                // Add to current user's contacts
                                val contactData = hashMapOf(
                                    "userId" to foundUserId,
                                    "displayName" to foundUserName,
                                    "email" to foundUserEmail,
                                    "photoUrl" to foundUserPhotoUrl,
                                    "addedAt" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                                )
                                
                                FirebaseFirestore.getInstance()
                                    .collection("users")
                                    .document(currentUser.uid)
                                    .collection("contacts")
                                    .document(foundUserId)
                                    .set(contactData)
                                    .addOnSuccessListener {
                                        isLoading = false
                                        onAddContact(email.trim())
                                    }
                                    .addOnFailureListener { e ->
                                        isLoading = false
                                        errorMessage = "Failed to add contact: ${e.message}"
                                    }
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