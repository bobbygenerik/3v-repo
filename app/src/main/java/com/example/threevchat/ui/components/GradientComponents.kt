package com.example.threevchat.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * A wrapper that adds a gradient border glow effect when the child is focused
 */
@Composable
fun GradientFocusWrapper(
    isGlowing: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val glowAlpha by animateFloatAsState(
        targetValue = if (isGlowing) 1f else 0f,
        animationSpec = tween(durationMillis = 200),
        label = "glow-alpha"
    )
    
    Box(modifier = modifier) {
        // Gradient border (visible when focused)
        if (glowAlpha > 0f) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .border(
                        width = 2.dp,
                        brush = Brush.horizontalGradient(
                            colors = listOf(
                                Color(0xFF3B82F6).copy(alpha = glowAlpha),
                                Color(0xFF8B5CF6).copy(alpha = glowAlpha),
                                Color(0xFFEC4899).copy(alpha = glowAlpha)
                            )
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
            )
        }
        
        // Content
        content()
    }
}

/**
 * A button with gradient border effect when pressed
 * Used for secondary actions like Contacts and History
 */
@Composable
fun GradientPressButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    backgroundColor: Color = Color(0xFF1A1A1A),
    content: @Composable RowScope.() -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    
    // Scale animation when pressed
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.95f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessLow
        ),
        label = "button-press-scale"
    )
    
    // Gradient border glow when pressed
    val gradientAlpha by animateFloatAsState(
        targetValue = if (isPressed) 0.6f else 0f,
        animationSpec = tween(durationMillis = 150),
        label = "gradient-alpha"
    )
    
    Box(
        modifier = modifier
            .scale(scale)
            .clip(RoundedCornerShape(12.dp))
    ) {
        // Gradient border overlay (visible when pressed)
        if (gradientAlpha > 0f) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .background(
                        brush = Brush.horizontalGradient(
                            colors = listOf(
                                Color(0xFF3B82F6).copy(alpha = gradientAlpha),
                                Color(0xFF8B5CF6).copy(alpha = gradientAlpha),
                                Color(0xFFEC4899).copy(alpha = gradientAlpha)
                            )
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
            )
        }
        
        // Main button
        Box(
            modifier = Modifier
                .matchParentSize()
                .padding(if (gradientAlpha > 0f) 2.dp else 0.dp)
                .background(backgroundColor, RoundedCornerShape(12.dp))
                .clickable(
                    interactionSource = interactionSource,
                    indication = null,
                    onClick = onClick
                ),
            contentAlignment = Alignment.Center
        ) {
            Row(
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
                content = content
            )
        }
    }
}

/**
 * Primary CTA button with gradient background
 * Used for main actions like Start Call
 */
@Composable
fun GradientCtaButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    
    // Scale animation when pressed
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.95f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessLow
        ),
        label = "cta-press-scale"
    )
    
    Box(
        modifier = modifier
            .scale(scale)
            .clip(RoundedCornerShape(12.dp))
            .background(
                brush = Brush.horizontalGradient(
                    colors = if (enabled) {
                        listOf(
                            Color(0xFF10B981),
                            Color(0xFF059669)
                        )
                    } else {
                        listOf(
                            Color(0xFF6B7280),
                            Color(0xFF4B5563)
                        )
                    }
                ),
                shape = RoundedCornerShape(12.dp)
            )
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
                enabled = enabled
            ),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            color = Color.White,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}