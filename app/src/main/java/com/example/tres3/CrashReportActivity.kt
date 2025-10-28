package com.example.tres3

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.Timestamp
import java.text.SimpleDateFormat
import java.util.Locale

data class CrashReport(
    val id: String,
    val message: String,
    val exceptionType: String,
    val timestamp: Timestamp,
    val stackTrace: String
)

class CrashReportActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            CrashReportScreen(onBackPressed = { finish() })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CrashReportScreen(onBackPressed: () -> Unit) {
    var reports by remember { mutableStateOf<List<CrashReport>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        val userId = FirebaseAuth.getInstance().currentUser?.uid
        if (userId == null) {
            error = "You must be logged in to view crash reports."
            isLoading = false
            return@LaunchedEffect
        }

        FirebaseFirestore.getInstance()
            .collection("crashes")
            .whereEqualTo("userId", userId)
            .orderBy("timestamp", Query.Direction.DESCENDING)
            .limit(20)
            .get()
            .addOnSuccessListener { snapshot ->
                reports = snapshot.documents.mapNotNull { doc ->
                    CrashReport(
                        id = doc.id,
                        message = doc.getString("message") ?: "N/A",
                        exceptionType = doc.getString("exceptionType") ?: "N/A",
                        timestamp = doc.getTimestamp("timestamp") ?: Timestamp.now(),
                        stackTrace = doc.getString("stackTrace") ?: "No stack trace available."
                    )
                }
                isLoading = false
            }
            .addOnFailureListener { e ->
                error = "Failed to load reports: ${e.message}"
                isLoading = false
            }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Crash Reports") },
                navigationIcon = {
                    IconButton(onClick = onBackPressed) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.BackgroundDark,
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White
                )
            )
        },
        containerColor = AppColors.BackgroundDark
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            if (isLoading) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
            } else if (error != null) {
                Text(
                    text = error!!,
                    color = Color.Red,
                    modifier = Modifier.align(Alignment.Center)
                )
            } else if (reports.isEmpty()) {
                Text(
                    text = "No crash reports found. That's good news!",
                    color = Color.Gray,
                    modifier = Modifier.align(Alignment.Center)
                )
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(reports) { report ->
                        CrashReportItem(report)
                    }
                }
            }
        }
    }
}

@Composable
fun CrashReportItem(report: CrashReport) {
    var expanded by remember { mutableStateOf(false) }
    val formatter = remember { SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = AppColors.Gray.copy(alpha = 0.1f)),
        onClick = { expanded = !expanded }
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = report.exceptionType.substringAfterLast('.'),
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
                color = Color.White
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = report.message,
                fontSize = 14.sp,
                color = Color.LightGray,
                maxLines = if (expanded) Int.MAX_VALUE else 2
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = formatter.format(report.timestamp.toDate()),
                fontSize = 12.sp,
                color = Color.Gray
            )
            if (expanded) {
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Full Stack Trace:",
                    fontWeight = FontWeight.Medium,
                    color = Color.White
                )
                Spacer(modifier = Modifier.height(4.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.Black.copy(alpha = 0.3f))
                        .padding(8.dp)
                ) {
                    Text(
                        text = report.stackTrace,
                        fontSize = 12.sp,
                        color = Color.Cyan.copy(alpha = 0.8f)
                    )
                }
            }
        }
    }
}
