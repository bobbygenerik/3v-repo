package com.example.tres3.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.tres3.analytics.AnalyticsDashboard
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * AnalyticsDashboardScreen - Comprehensive analytics UI with charts and metrics
 * 
 * Features:
 * - Real-time metrics display (quality, latency, CPU, memory)
 * - Line charts for trend visualization
 * - Circular progress indicators
 * - Call history list with details
 * - Summary cards with key statistics
 * - Time range filtering (24h, 7d, 30d, All)
 * - Export functionality
 * - Animated metric updates
 * 
 * Integrates with:
 * - AnalyticsDashboard for data retrieval
 * - Material3 for modern UI components
 * - Compose Canvas for custom charts
 * 
 * Usage:
 * ```kotlin
 * AnalyticsDashboardScreen(
 *     dashboard = analyticsDashboard,
 *     modifier = Modifier.fillMaxSize()
 * )
 * ```
 */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnalyticsDashboardScreen(
    dashboard: AnalyticsDashboard,
    modifier: Modifier = Modifier,
    onClose: (() -> Unit)? = null
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    
    // Time range filter
    var timeRange by remember { mutableStateOf(TimeRange.DAY) }
    
    // Data state
    var summary by remember { mutableStateOf(dashboard.generateSummary()) }
    var videoQualityHistory by remember { 
        mutableStateOf(dashboard.getMetricHistory(AnalyticsDashboard.MetricType.VIDEO_QUALITY))
    }
    var audioQualityHistory by remember {
        mutableStateOf(dashboard.getMetricHistory(AnalyticsDashboard.MetricType.AUDIO_QUALITY))
    }
    var latencyHistory by remember {
        mutableStateOf(dashboard.getMetricHistory(AnalyticsDashboard.MetricType.NETWORK_LATENCY))
    }
    
    // Refresh data
    fun refreshData() {
        val timeRangeMs = when (timeRange) {
            TimeRange.HOUR -> 60 * 60 * 1000L
            TimeRange.DAY -> 24 * 60 * 60 * 1000L
            TimeRange.WEEK -> 7 * 24 * 60 * 60 * 1000L
            TimeRange.MONTH -> 30 * 24 * 60 * 60 * 1000L
            TimeRange.ALL -> null
        }
        
        summary = dashboard.generateSummary(timeRangeMs)
        
        val startTime = timeRangeMs?.let { System.currentTimeMillis() - it }
        videoQualityHistory = dashboard.getMetricHistory(
            AnalyticsDashboard.MetricType.VIDEO_QUALITY,
            startTime = startTime
        )
        audioQualityHistory = dashboard.getMetricHistory(
            AnalyticsDashboard.MetricType.AUDIO_QUALITY,
            startTime = startTime
        )
        latencyHistory = dashboard.getMetricHistory(
            AnalyticsDashboard.MetricType.NETWORK_LATENCY,
            startTime = startTime
        )
    }
    
    // Auto-refresh every 5 seconds
    LaunchedEffect(timeRange) {
        while (true) {
            refreshData()
            delay(5000)
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Analytics Dashboard") },
                navigationIcon = {
                    if (onClose != null) {
                        IconButton(onClick = onClose) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Close")
                        }
                    }
                },
                actions = {
                    // Export button
                    IconButton(onClick = {
                        scope.launch {
                            val report = dashboard.generateReport(AnalyticsDashboard.ReportFormat.TEXT)
                            // TODO: Share or save report
                        }
                    }) {
                        Icon(Icons.Default.Download, contentDescription = "Export")
                    }
                    
                    // Refresh button
                    IconButton(onClick = { refreshData() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color(0xFF1b1c1e),
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White,
                    actionIconContentColor = Color.White
                )
            )
        },
        containerColor = Color(0xFF1b1c1e)
    ) { paddingValues ->
        LazyColumn(
            modifier = modifier
                .padding(paddingValues)
                .fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Time range selector
            item {
                TimeRangeSelector(
                    selectedRange = timeRange,
                    onRangeSelected = { timeRange = it }
                )
            }
            
            // Summary cards
            item {
                SummaryCards(summary = summary)
            }
            
            // Quality metrics section
            item {
                SectionHeader(
                    title = "Quality Metrics",
                    icon = Icons.Default.TrendingUp
                )
            }
            
            item {
                QualityMetricsCard(
                    videoQuality = summary.averageQuality,
                    audioQuality = dashboard.getAverageMetric(
                        AnalyticsDashboard.MetricType.AUDIO_QUALITY,
                        timeRange.toMilliseconds()
                    ).roundToInt(),
                    qualityTrend = summary.qualityTrend
                )
            }
            
            // Charts section
            item {
                SectionHeader(
                    title = "Trend Analysis",
                    icon = Icons.Default.BarChart
                )
            }
            
            item {
                LineChartCard(
                    title = "Video Quality",
                    data = videoQualityHistory.map { it.value },
                    color = Color(0xFF4CAF50),
                    unit = "%"
                )
            }
            
            item {
                LineChartCard(
                    title = "Audio Quality",
                    data = audioQualityHistory.map { it.value },
                    color = Color(0xFF2196F3),
                    unit = "%"
                )
            }
            
            item {
                LineChartCard(
                    title = "Network Latency",
                    data = latencyHistory.map { it.value },
                    color = Color(0xFFFF9800),
                    unit = "ms"
                )
            }
            
            // Common issues section
            if (summary.mostCommonIssues.isNotEmpty()) {
                item {
                    SectionHeader(
                        title = "Common Issues",
                        icon = Icons.Default.Warning
                    )
                }
                
                item {
                    CommonIssuesCard(issues = summary.mostCommonIssues)
                }
            }
            
            // Usage statistics
            item {
                SectionHeader(
                    title = "Usage Statistics",
                    icon = Icons.Default.Analytics
                )
            }
            
            item {
                UsageStatsCard(summary = summary)
            }
        }
    }
}

/**
 * Time range enum
 */
enum class TimeRange(val label: String) {
    HOUR("1H"),
    DAY("24H"),
    WEEK("7D"),
    MONTH("30D"),
    ALL("All");
    
    fun toMilliseconds(): Long? = when (this) {
        HOUR -> 60 * 60 * 1000L
        DAY -> 24 * 60 * 60 * 1000L
        WEEK -> 7 * 24 * 60 * 60 * 1000L
        MONTH -> 30 * 24 * 60 * 60 * 1000L
        ALL -> null
    }
}

/**
 * Time range selector
 */
@Composable
private fun TimeRangeSelector(
    selectedRange: TimeRange,
    onRangeSelected: (TimeRange) -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp)),
        color = Color(0xFF2c2d2f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            TimeRange.values().forEach { range ->
                Surface(
                    onClick = { onRangeSelected(range) },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(8.dp),
                    color = if (range == selectedRange) {
                        Color(0xFF6B7FB8)
                    } else {
                        Color.Transparent
                    }
                ) {
                    Text(
                        text = range.label,
                        color = Color.White,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = if (range == selectedRange) FontWeight.Bold else FontWeight.Normal,
                        modifier = Modifier.padding(vertical = 12.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                }
            }
        }
    }
}

/**
 * Summary cards row
 */
@Composable
private fun SummaryCards(
    summary: AnalyticsDashboard.AnalyticsSummary,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        MetricCard(
            title = "Total Calls",
            value = summary.totalCalls.toString(),
            icon = Icons.Default.Phone,
            color = Color(0xFF4CAF50),
            modifier = Modifier.weight(1f)
        )
        
        MetricCard(
            title = "Avg Duration",
            value = formatDuration(summary.averageDuration),
            icon = Icons.Default.Timer,
            color = Color(0xFF2196F3),
            modifier = Modifier.weight(1f)
        )
        
        MetricCard(
            title = "Avg Quality",
            value = "${summary.averageQuality}%",
            icon = Icons.Default.HighQuality,
            color = Color(0xFFFF9800),
            modifier = Modifier.weight(1f)
        )
    }
}

/**
 * Individual metric card
 */
@Composable
private fun MetricCard(
    title: String,
    value: String,
    icon: ImageVector,
    color: Color,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        color = Color(0xFF2c2d2f)
    ) {
        Column(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Surface(
                modifier = Modifier.size(40.dp),
                shape = CircleShape,
                color = color.copy(alpha = 0.2f)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = color,
                        modifier = Modifier.size(24.dp)
                    )
                }
            }
            
            Text(
                text = value,
                color = Color.White,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            
            Text(
                text = title,
                color = Color(0xFFAAAAAA),
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

/**
 * Quality metrics card with circular progress
 */
@Composable
private fun QualityMetricsCard(
    videoQuality: Int,
    audioQuality: Int,
    qualityTrend: String,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = Color(0xFF2c2d2f)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Average Quality",
                    color = Color.White,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                
                TrendBadge(trend = qualityTrend)
            }
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                CircularProgressIndicator(
                    label = "Video",
                    value = videoQuality,
                    color = Color(0xFF4CAF50)
                )
                
                CircularProgressIndicator(
                    label = "Audio",
                    value = audioQuality,
                    color = Color(0xFF2196F3)
                )
            }
        }
    }
}

/**
 * Circular progress indicator
 */
@Composable
private fun CircularProgressIndicator(
    label: String,
    value: Int,
    color: Color,
    modifier: Modifier = Modifier
) {
    val animatedValue by animateFloatAsState(
        targetValue = value / 100f,
        animationSpec = tween(1000),
        label = "progress"
    )
    
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier.size(100.dp),
            contentAlignment = Alignment.Center
        ) {
            // Background circle
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawArc(
                    color = Color(0xFF404040),
                    startAngle = -90f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = Stroke(width = 12.dp.toPx())
                )
            }
            
            // Progress arc
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawArc(
                    color = color,
                    startAngle = -90f,
                    sweepAngle = 360f * animatedValue,
                    useCenter = false,
                    style = Stroke(width = 12.dp.toPx())
                )
            }
            
            // Value text
            Text(
                text = "$value%",
                color = Color.White,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
        }
        
        Text(
            text = label,
            color = Color(0xFFAAAAAA),
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

/**
 * Trend badge
 */
@Composable
private fun TrendBadge(
    trend: String,
    modifier: Modifier = Modifier
) {
    val (color, icon) = when (trend) {
        "Improving" -> Color(0xFF4CAF50) to Icons.Default.TrendingUp
        "Degrading" -> Color(0xFFF44336) to Icons.Default.TrendingDown
        "Stable" -> Color(0xFF2196F3) to Icons.Default.TrendingFlat
        else -> Color(0xFF888888) to Icons.Default.Help
    }
    
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = color.copy(alpha = 0.2f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(16.dp)
            )
            Text(
                text = trend,
                color = color,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

/**
 * Line chart card
 */
@Composable
private fun LineChartCard(
    title: String,
    data: List<Float>,
    color: Color,
    unit: String,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = Color(0xFF2c2d2f)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = title,
                    color = Color.White,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                
                if (data.isNotEmpty()) {
                    Text(
                        text = "${data.lastOrNull()?.roundToInt() ?: 0}$unit",
                        color = color,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            
            if (data.isNotEmpty()) {
                LineChart(
                    data = data,
                    color = color,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp)
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "No data available",
                        color = Color(0xFF888888),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }
    }
}

/**
 * Line chart component
 */
@Composable
private fun LineChart(
    data: List<Float>,
    color: Color,
    modifier: Modifier = Modifier
) {
    Canvas(modifier = modifier) {
        if (data.size < 2) return@Canvas
        
        val maxValue = data.maxOrNull() ?: 100f
        val minValue = data.minOrNull() ?: 0f
        val range = max(maxValue - minValue, 1f)
        
        val xStep = size.width / (data.size - 1)
        val path = Path()
        
        // Build path
        data.forEachIndexed { index, value ->
            val x = index * xStep
            val normalizedValue = (value - minValue) / range
            val y = size.height - (normalizedValue * size.height)
            
            if (index == 0) {
                path.moveTo(x, y)
            } else {
                path.lineTo(x, y)
            }
        }
        
        // Draw gradient fill
        val gradientBrush = Brush.verticalGradient(
            colors = listOf(
                color.copy(alpha = 0.3f),
                Color.Transparent
            )
        )
        
        val fillPath = Path().apply {
            addPath(path)
            lineTo(size.width, size.height)
            lineTo(0f, size.height)
            close()
        }
        
        drawPath(
            path = fillPath,
            brush = gradientBrush
        )
        
        // Draw line
        drawPath(
            path = path,
            color = color,
            style = Stroke(width = 3.dp.toPx())
        )
        
        // Draw data points
        data.forEachIndexed { index, value ->
            val x = index * xStep
            val normalizedValue = (value - minValue) / range
            val y = size.height - (normalizedValue * size.height)
            
            drawCircle(
                color = color,
                radius = 4.dp.toPx(),
                center = Offset(x, y)
            )
        }
    }
}

/**
 * Common issues card
 */
@Composable
private fun CommonIssuesCard(
    issues: List<Pair<String, Int>>,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = Color(0xFF2c2d2f)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            issues.forEach { (issue, count) ->
                IssueRow(issue = issue, count = count)
            }
        }
    }
}

/**
 * Individual issue row
 */
@Composable
private fun IssueRow(
    issue: String,
    count: Int,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.weight(1f)
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                tint = Color(0xFFFF9800),
                modifier = Modifier.size(20.dp)
            )
            Text(
                text = issue,
                color = Color.White,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        
        Surface(
            shape = RoundedCornerShape(12.dp),
            color = Color(0xFF404040)
        ) {
            Text(
                text = count.toString(),
                color = Color.White,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
            )
        }
    }
}

/**
 * Usage statistics card
 */
@Composable
private fun UsageStatsCard(
    summary: AnalyticsDashboard.AnalyticsSummary,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = Color(0xFF2c2d2f)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            StatRow(
                label = "Total Duration",
                value = formatDuration(summary.totalDuration),
                icon = Icons.Default.AccessTime
            )
            
            StatRow(
                label = "Average Participants",
                value = summary.averageParticipants.toString(),
                icon = Icons.Default.People
            )
            
            StatRow(
                label = "Peak Usage",
                value = "${summary.peakUsageHour}:00",
                icon = Icons.Default.Schedule
            )
        }
    }
}

/**
 * Individual stat row
 */
@Composable
private fun StatRow(
    label: String,
    value: String,
    icon: ImageVector,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = Color(0xFF6B7FB8),
                modifier = Modifier.size(24.dp)
            )
            Text(
                text = label,
                color = Color(0xFFAAAAAA),
                style = MaterialTheme.typography.bodyMedium
            )
        }
        
        Text(
            text = value,
            color = Color.White,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Bold
        )
    }
}

/**
 * Section header
 */
@Composable
private fun SectionHeader(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = Color(0xFF6B7FB8),
            modifier = Modifier.size(24.dp)
        )
        Text(
            text = title,
            color = Color.White,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )
    }
}

/**
 * Format duration helper
 */
private fun formatDuration(durationMs: Long): String {
    val seconds = durationMs / 1000
    val minutes = seconds / 60
    val hours = minutes / 60
    
    return when {
        hours > 0 -> "${hours}h ${minutes % 60}m"
        minutes > 0 -> "${minutes}m"
        else -> "${seconds}s"
    }
}
