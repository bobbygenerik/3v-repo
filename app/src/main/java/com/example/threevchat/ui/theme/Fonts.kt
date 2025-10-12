package com.example.threevchat.ui

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.googlefonts.Font as GoogleFontTypeface
import androidx.compose.ui.text.googlefonts.GoogleFont
import androidx.compose.ui.text.googlefonts.GoogleFont.Provider
import com.example.threevchat.R

// Downloadable Google Fonts provider via Play Services
private val provider = Provider(
    providerAuthority = "com.google.android.gms.fonts",
    providerPackage = "com.google.android.gms",
    certificates = R.array.com_google_android_gms_fonts_certs
)

private val interFamily: FontFamily = FontFamily(
    GoogleFontTypeface(GoogleFont("Inter"), provider, FontWeight.Normal),
    GoogleFontTypeface(GoogleFont("Inter"), provider, FontWeight.Medium),
    GoogleFontTypeface(GoogleFont("Inter"), provider, FontWeight.SemiBold),
    GoogleFontTypeface(GoogleFont("Inter"), provider, FontWeight.Bold)
)

private val montserratFamily: FontFamily = FontFamily(
    GoogleFontTypeface(GoogleFont("Montserrat"), provider, FontWeight.Normal),
    GoogleFontTypeface(GoogleFont("Montserrat"), provider, FontWeight.Medium),
    GoogleFontTypeface(GoogleFont("Montserrat"), provider, FontWeight.SemiBold),
    GoogleFontTypeface(GoogleFont("Montserrat"), provider, FontWeight.Bold)
)

val AppTypography = androidx.compose.material3.Typography(
    displayLarge = TextStyle(fontFamily = montserratFamily),
    displayMedium = TextStyle(fontFamily = montserratFamily),
    displaySmall = TextStyle(fontFamily = montserratFamily),
    headlineLarge = TextStyle(fontFamily = montserratFamily),
    headlineMedium = TextStyle(fontFamily = montserratFamily),
    headlineSmall = TextStyle(fontFamily = montserratFamily),
    titleLarge = TextStyle(fontFamily = interFamily),
    titleMedium = TextStyle(fontFamily = interFamily),
    titleSmall = TextStyle(fontFamily = interFamily),
    bodyLarge = TextStyle(fontFamily = interFamily),
    bodyMedium = TextStyle(fontFamily = interFamily),
    bodySmall = TextStyle(fontFamily = interFamily),
    labelLarge = TextStyle(fontFamily = interFamily),
    labelMedium = TextStyle(fontFamily = interFamily),
    labelSmall = TextStyle(fontFamily = interFamily)
)
