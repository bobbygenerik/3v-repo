// Backup of HomeScreen before replacing layout
// Saved on 2025-10-08

package com.example.threevchat.ui.screens

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AlternateEmail
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.example.threevchat.R
import com.example.threevchat.data.UserRepository
import com.example.threevchat.ui.theme.AppColors
import com.example.threevchat.ui.theme.AppTypography
import com.example.threevchat.viewmodel.MainViewModel

private val interFontFamily: FontFamily get() = AppTypography.bodyLarge.fontFamily ?: FontFamily.Default
private val montserratFontFamily: FontFamily get() = AppTypography.displayLarge.fontFamily ?: FontFamily.Default

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun HomeScreen(
    vm: MainViewModel,
    onStartCall: () -> Unit,
    onViewCallLogs: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenSettings: () -> Unit,
    onSignOut: () -> Unit
) {
    var callee by remember { mutableStateOf("") }
    val ctx = LocalContext.current
    var contacts by remember { mutableStateOf(listOf<String>()) }
    var showSuggestions by remember { mutableStateOf(false) }
    var profileUrl by remember { mutableStateOf<String?>(null) }

    val pickEmail = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { res ->
        if (res.resultCode == Activity.RESULT_OK) {
            val uri = res.data?.data
            if (uri != null) {
                val c = ctx.contentResolver.query(
                    uri,
                    arrayOf(ContactsContract.CommonDataKinds.Email.ADDRESS),
                    null, null, null
                )
                c?.use { cur ->
                    if (cur.moveToFirst()) {
                        val idx = cur.getColumnIndex(ContactsContract.CommonDataKinds.Email.ADDRESS)
                        if (idx >= 0) callee = cur.getString(idx)
                    }
                }
            }
        }
    }

    val requestContacts = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Email.CONTENT_URI)
            pickEmail.launch(intent)
        } else {
            android.widget.Toast.makeText(ctx, "Contacts permission denied", android.widget.Toast.LENGTH_SHORT).show()
        }
    }

    LaunchedEffect(Unit) {
        val repo = UserRepository(ctx.applicationContext as Application)
        val prof = repo.getProfile()
        if (prof.isSuccess) profileUrl = prof.getOrNull()?.photoUrl

        val granted = androidx.core.content.ContextCompat.checkSelfPermission(
            ctx, Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            val list = mutableListOf<String>()
            val cursor = ctx.contentResolver.query(
                ContactsContract.CommonDataKinds.Email.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Email.ADDRESS),
                null, null, null
            )
            cursor?.use { c ->
                val idx = c.getColumnIndex(ContactsContract.CommonDataKinds.Email.ADDRESS)
                while (c.moveToNext()) {
                    if (idx >= 0) list += c.getString(idx)
                }
            }
            contacts = list.distinct().sorted()
        }
    }

    var showProfileMenu by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {},
                actions = {
                    Box {
                        IconButton(onClick = { showProfileMenu = true }) {
                            if (profileUrl != null) {
                                AsyncImage(
                                    model = profileUrl,
                                    contentDescription = "Profile",
                                    modifier = Modifier
                                        .size(30.dp)
                                        .clip(CircleShape)
                                        .background(Color.White.copy(alpha = 0.12f), CircleShape),
                                    contentScale = ContentScale.Crop,
                                    placeholder = painterResource(id = R.drawable.ic_person),
                                    error = painterResource(id = R.drawable.ic_person)
                                )
                            } else {
                                androidx.compose.foundation.Image(
                                    painter = painterResource(id = R.drawable.ic_person),
                                    contentDescription = "Profile",
                                    modifier = Modifier
                                        .size(30.dp)
                                        .clip(CircleShape)
                                        .background(Color.White.copy(alpha = 0.12f), CircleShape),
                                    colorFilter = androidx.compose.ui.graphics.ColorFilter.tint(Color.White)
                                )
                            }
                        }
                        DropdownMenu(
                            expanded = showProfileMenu,
                            onDismissRequest = { showProfileMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Profile") },
                                onClick = { showProfileMenu = false; onOpenProfile() }
                            )
                            DropdownMenuItem(
                                text = { Text("Settings") },
                                onClick = { showProfileMenu = false; onOpenSettings() }
                            )
                            DropdownMenuItem(
                                text = { Text("Sign out", color = Color.Red) },
                                onClick = { showProfileMenu = false; vm.signOut(); onSignOut() }
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Black,
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White,
                    actionIconContentColor = Color.White
                )
            )
        },
        containerColor = Color.Black
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentAlignment = Alignment.Center
        ) {
        Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 520.dp)
                    .aspectRatio(9f / 16f)
            .padding(16.dp)
                    .border(4.dp, AppColors.PhoneContainerBorder, RoundedCornerShape(48.dp))
                    .clip(RoundedCornerShape(48.dp))
                    .padding(8.dp)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(40.dp))
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    // Centered logo replacing the helper text
            androidx.compose.foundation.Image(
                        painter = painterResource(id = R.drawable.logo_adobe_express),
                        contentDescription = "Logo",
                        modifier = Modifier
                .height(192.dp)
                            .fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))

                    // Push the inputs/actions toward the bottom for thumb ergonomics
                    Spacer(modifier = Modifier.weight(1f))

                    OutlinedTextField(
                        value = callee,
                        onValueChange = { text ->
                            callee = text
                            showSuggestions = text.isNotBlank()
                        },
                        singleLine = true,
                        leadingIcon = { Icon(imageVector = Icons.Filled.AlternateEmail, contentDescription = null, tint = AppColors.TextSecondary) },
                        placeholder = { Text("Search", color = AppColors.TextSecondary) },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = AppColors.AccentGreen,
                            unfocusedBorderColor = AppColors.InputBorder,
                            focusedContainerColor = AppColors.InputBg,
                            unfocusedContainerColor = AppColors.InputBg,
                            focusedTextColor = AppColors.TextPrimary,
                            unfocusedTextColor = AppColors.TextPrimary,
                        ),
                        shape = RoundedCornerShape(8.dp),
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (showSuggestions && callee.isNotBlank()) {
                        val filtered = remember(callee, contacts) {
                            contacts.filter { it.contains(callee, ignoreCase = true) }.take(6)
                        }
                        if (filtered.isNotEmpty()) {
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.fillMaxWidth()) {
                                filtered.forEach { suggestion ->
                                    TextButton(
                                        onClick = {
                                            callee = suggestion
                                            showSuggestions = false
                                        },
                                        colors = ButtonDefaults.textButtonColors(contentColor = AppColors.AccentGreen)
                                    ) { Text(suggestion) }
                                }
                            }
                        }
                    }

                    // Row of Contacts and Call Logs side by side
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedButton(
                            onClick = {
                                val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                                    ctx, Manifest.permission.READ_CONTACTS
                                ) == PackageManager.PERMISSION_GRANTED
                                if (granted) {
                                    val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Email.CONTENT_URI)
                                    pickEmail.launch(intent)
                                } else {
                                    requestContacts.launch(Manifest.permission.READ_CONTACTS)
                                }
                            },
                            modifier = Modifier
                                .weight(1f)
                                .height(50.dp),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent, contentColor = AppColors.AccentGreen)
                        ) {
                            Icon(imageVector = Icons.Filled.People, contentDescription = null, modifier = Modifier.size(18.dp), tint = AppColors.AccentGreen)
                            Spacer(Modifier.width(8.dp))
                            Text("Contacts", fontFamily = interFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = AppColors.AccentGreen)
                        }

                        OutlinedButton(
                            onClick = { onViewCallLogs() },
                            modifier = Modifier
                                .weight(1f)
                                .height(50.dp),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent, contentColor = AppColors.AccentGreen)
                        ) {
                            Icon(imageVector = Icons.Filled.History, contentDescription = null, modifier = Modifier.size(18.dp), tint = AppColors.AccentGreen)
                            Spacer(Modifier.width(8.dp))
                            Text("Call Logs", fontFamily = interFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = AppColors.AccentGreen)
                        }
                    }

                    // Start Call button with gradient background to match logo theme
                    val gradient = androidx.compose.ui.graphics.Brush.horizontalGradient(
                        colors = listOf(Color(0xFF00C853), Color(0xFF00E5FF))
                    )
                    Button(
                        onClick = {
                            if (callee.isBlank()) {
                                android.widget.Toast.makeText(ctx, "Please enter a recipient before starting a call", android.widget.Toast.LENGTH_SHORT).show()
                            } else {
                                vm.startCallTo(callee)
                                onStartCall()
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(gradient),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent, contentColor = Color.White)
                    ) {
                        Icon(imageVector = Icons.Filled.Phone, contentDescription = null, modifier = Modifier.size(20.dp), tint = Color.White)
                        Spacer(Modifier.width(8.dp))
                        Text("Start Call", fontFamily = montserratFontFamily, fontWeight = FontWeight.Bold, fontSize = 18.sp, color = Color.White)
                    }

                    Spacer(modifier = Modifier.height(8.dp))
                }
            }
        }
    }
}
