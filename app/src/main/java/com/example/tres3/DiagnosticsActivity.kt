package com.example.tres3

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.tres3.camera.Camera2Manager
import com.example.tres3.ml.MLKitManager
import com.example.tres3.opencv.OpenCVManager
import com.example.tres3.video.VideoCodecManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * DiagnosticsActivity - Shows status of all video enhancement features
 * Useful for debugging and verifying feature availability
 */
class DiagnosticsActivity : AppCompatActivity() {
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        setContent {
            DiagnosticsScreen()
        }
    }
    
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun DiagnosticsScreen() {
        val scope = rememberCoroutineScope()
        var diagnosticsData by remember { mutableStateOf<Map<String, Any>>(emptyMap()) }
        var isLoading by remember { mutableStateOf(true) }
        
        LaunchedEffect(Unit) {
            scope.launch {
                diagnosticsData = loadDiagnostics()
                isLoading = false
            }
        }
        
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Enhancement Diagnostics") },
                    navigationIcon = {
                        IconButton(onClick = { finish() }) {
                            Icon(Icons.Default.ArrowBack, "Back")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.BackgroundDark,
                        titleContentColor = AppColors.TextLight
                    )
                )
            },
            containerColor = AppColors.BackgroundDark
        ) { paddingValues ->
            if (isLoading) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = AppColors.PrimaryBlue)
                }
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    // Feature Flags Section
                    DiagnosticSection(
                        title = "Feature Flags",
                        data = diagnosticsData["featureFlags"] as? Map<String, Any> ?: emptyMap()
                    )
                    
                    // Video Codec Section
                    DiagnosticSection(
                        title = "Video Codecs",
                        data = diagnosticsData["videoCodec"] as? Map<String, Any> ?: emptyMap()
                    )
                    
                    // Camera2 Section
                    DiagnosticSection(
                        title = "Camera2 API",
                        data = diagnosticsData["camera2"] as? Map<String, Any> ?: emptyMap()
                    )
                    
                    // ML Kit Section
                    DiagnosticSection(
                        title = "ML Kit",
                        data = diagnosticsData["mlKit"] as? Map<String, Any> ?: emptyMap()
                    )
                    
                    // OpenCV Section
                    DiagnosticSection(
                        title = "OpenCV",
                        data = diagnosticsData["openCV"] as? Map<String, Any> ?: emptyMap()
                    )
                }
            }
        }
    }
    
    @Composable
    fun DiagnosticSection(title: String, data: Map<String, Any>) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(containerColor = AppColors.Gray.copy(alpha = 0.2f))
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = title,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.TextLight
                )
                
                Divider(color = AppColors.Gray.copy(alpha = 0.3f), thickness = 1.dp)
                
                if (data.isEmpty()) {
                    Text(
                        text = "No data available",
                        fontSize = 14.sp,
                        color = AppColors.TextLight.copy(alpha = 0.6f)
                    )
                } else {
                    data.forEach { (key, value) ->
                        DiagnosticItem(key, value)
                    }
                }
            }
        }
    }
    
    @Composable
    fun DiagnosticItem(key: String, value: Any) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = key.replace(Regex("([A-Z])"), " $1").trim()
                    .replaceFirstChar { it.uppercase() },
                fontSize = 14.sp,
                color = AppColors.TextLight.copy(alpha = 0.8f),
                modifier = Modifier.weight(1f)
            )
            
            when (value) {
                is Boolean -> {
                    Icon(
                        imageVector = if (value) Icons.Default.CheckCircle else Icons.Default.Error,
                        contentDescription = null,
                        tint = if (value) Color(0xFF4CAF50) else Color(0xFFFF5252),
                        modifier = Modifier.size(20.dp)
                    )
                }
                is Number -> {
                    Text(
                        text = value.toString(),
                        fontSize = 14.sp,
                        color = AppColors.PrimaryBlue,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                else -> {
                    Text(
                        text = value.toString(),
                        fontSize = 14.sp,
                        color = AppColors.TextLight,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }
    }
    
    private suspend fun loadDiagnostics(): Map<String, Any> = withContext(Dispatchers.IO) {
        mapOf(
            "featureFlags" to mapOf(
                "advancedCodecs" to FeatureFlags.isAdvancedCodecsEnabled(),
                "cameraEnhancements" to FeatureFlags.isCameraEnhancementsEnabled(),
                "mlKitEnabled" to FeatureFlags.isMLKitEnabled(),
                "backgroundBlur" to FeatureFlags.isBackgroundBlurEnabled(),
                "virtualBackground" to FeatureFlags.isVirtualBackgroundEnabled(),
                "faceEnhancement" to FeatureFlags.isFaceEnhancementEnabled(),
                "autofocusEnhanced" to FeatureFlags.isCameraAutofocusEnhanced(),
                "stabilization" to FeatureFlags.isCameraStabilizationEnabled(),
                "lowLight" to FeatureFlags.isCameraLowLightEnabled(),
                "developerMode" to FeatureFlags.isDeveloperModeEnabled(),
                "performanceOverlay" to FeatureFlags.isPerformanceOverlayEnabled(),
                "verboseLogging" to FeatureFlags.isVerboseLoggingEnabled()
            ),
            "videoCodec" to VideoCodecManager.getCodecStatus(this@DiagnosticsActivity),
            "camera2" to Camera2Manager.getCameraEnhancementStatus(this@DiagnosticsActivity),
            "mlKit" to MLKitManager.getMLKitStatus(),
            "openCV" to OpenCVManager.getStatus()
        )
    }
}
