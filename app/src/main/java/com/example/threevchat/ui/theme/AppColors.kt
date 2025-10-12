package com.example.threevchat.ui.theme

import androidx.compose.ui.graphics.Color

object AppColors {
    // Primary colors
    val Primary = Color(0xFF3CB371)  // Medium Sea Green
    val Secondary = Color(0xFF00BFFF) // Deep Sky Blue
    
    // Background colors
    val Background = Color(0xFF0A0F2B)
    val BackgroundGradientStart = Color(0xFF0A0F2B)
    val BackgroundGradientMiddle = Color(0xFF102A43)
    val BackgroundGradientEnd = Color(0xFF0B2C5D)
    
    // Surface colors
    val Surface = Color(0xFF1A1A1A)
    val SurfaceVariant = Color(0xFF2A2A2A)
    
    // Text colors
    val TextPrimary = Color.White
    val TextSecondary = Color(0xFFB0B0B0)
    val TextTertiary = Color(0xFF808080)
    
    // Input colors
    val InputBackground = Color(0xFF1A1A1A)
    val InputBorder = Color(0xFF3A3A3A)
    val InputFocusBorder = Color(0xFF3CB371)
    
    // Status colors
    val Success = Color(0xFF3CB371)
    val Error = Color(0xFFFF4444)
    val Warning = Color(0xFFFFAA00)
    val Info = Color(0xFF00BFFF)
    
    // Overlay colors
    val OverlayLight = Color.White.copy(alpha = 0.1f)
    val OverlayMedium = Color.White.copy(alpha = 0.2f)
    val OverlayDark = Color.Black.copy(alpha = 0.6f)
}