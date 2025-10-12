package com.example.threevchat.ui

import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.graphicsLayer
import kotlinx.coroutines.delay
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Shared Três3 wordmark.
 *
 * - "Três" in Blue (#00BFFF)
 * - trailing "3" in Green (#3CB371)
 */
@Composable
fun Tres3Logo(
    modifier: Modifier = Modifier,
    fontSize: TextUnit = 42.sp,
    fontWeight: FontWeight = FontWeight.ExtraBold,
    blue: Color = Color(0xFF00BFFF),
    green: Color = Color(0xFF3CB371),
    textAlign: TextAlign = TextAlign.Center,
) {
    // Flicker-in animation for the whole logo
    val flickerAlpha = remember { androidx.compose.animation.core.Animatable(0f) }
    LaunchedEffect(Unit) {
        repeat(3) {
            flickerAlpha.animateTo(1f, animationSpec = androidx.compose.animation.core.tween(80))
            flickerAlpha.animateTo(0f, animationSpec = androidx.compose.animation.core.tween(80))
        }
        flickerAlpha.animateTo(1f, animationSpec = androidx.compose.animation.core.tween(400))
    }
    Row(
        modifier = modifier.wrapContentSize(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val alpha = flickerAlpha.value
        listOf('T', 'r', 'ê', 's').forEach { c ->
            Text(
                text = c.toString(),
                color = blue.copy(alpha = alpha),
                fontSize = fontSize,
                fontWeight = fontWeight,
                textAlign = textAlign,
                style = MaterialTheme.typography.headlineLarge,
            )
        }
        Text(
            text = "3",
            color = green.copy(alpha = alpha),
            fontSize = fontSize,
            fontWeight = fontWeight,
            textAlign = textAlign,
            style = MaterialTheme.typography.headlineLarge,
        )
    }
}
