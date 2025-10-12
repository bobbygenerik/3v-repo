package com.example.threevchat.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.threevchat.ui.theme.AppColors
import com.example.threevchat.ui.theme.AppTypography
import com.example.threevchat.ui.components.GradientFocusWrapper
import com.example.threevchat.ui.components.GradientCtaButton
import kotlinx.coroutines.delay

private val interFontFamily: FontFamily 
    get() = AppTypography.bodyLarge.fontFamily ?: FontFamily.Default

private val montserratFontFamily: FontFamily 
    get() = AppTypography.displayLarge.fontFamily ?: FontFamily.Default

@Composable
fun SignInScreen(
    onSignIn: (credential: String, password: String) -> Unit = { _, _ -> },
    onForgotPassword: (email: String) -> Unit = {},
    onSignUp: () -> Unit = {}
) {
    var credential by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var credFocused by remember { mutableStateOf(false) }
    var passFocused by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        Color(0xFF0A0F2B),
                        Color(0xFF102A43),
                        Color(0xFF0B2C5D)
                    )
                )
            )
            .padding(24.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            // Logo with independent letter flicker animation
            val letters = remember { "Três".toList() }
            var letterAlphas by remember { mutableStateOf(List(letters.size) { 0f }) }
            var numberAlpha by remember { mutableStateOf(0f) }
            
            LaunchedEffect(Unit) {
                // Each letter flickers independently with random patterns
                for (index in letters.indices) {
                    val randomFlickers = listOf(
                        0f to 80L,
                        1f to 60L,
                        0.3f to 40L,
                        1f to 70L,
                        0.2f to 50L
                    ).shuffled().take(3)

                    // Random start delay for each letter
                    delay((50L..150L).random())

                    // Do the flicker sequence
                    for ((alpha, delayTime) in randomFlickers) {
                        letterAlphas = letterAlphas.toMutableList().apply {
                            this[index] = alpha
                        }
                        delay(delayTime)
                    }
                }

                // All letters flicker on together
                delay(1000L)
                letterAlphas = List(letters.size) { 0.3f }
                delay(60L)
                letterAlphas = List(letters.size) { 1f }
                delay(80L)
                letterAlphas = List(letters.size) { 0.5f }
                delay(50L)
                letterAlphas = List(letters.size) { 1f }

                // Finally, the "3" flickers on last
                delay(150L)
                numberAlpha = 0.4f
                delay(60L)
                numberAlpha = 1f
                delay(70L)
                numberAlpha = 0.3f
                delay(50L)
                numberAlpha = 1f
            }
            
            Row(verticalAlignment = Alignment.CenterVertically) {
                // Each letter flickers independently
                letters.forEachIndexed { index, char ->
                    Text(
                        text = char.toString(),
                        fontSize = 48.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF00BFFF),
                        fontFamily = montserratFontFamily,
                        modifier = Modifier.graphicsLayer { 
                            alpha = letterAlphas.getOrNull(index) ?: 0f
                        }
                    )
                }
                
                // The "3" flickers on last
                Text(
                    text = "3",
                    fontSize = 48.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF3CB371),
                    fontFamily = montserratFontFamily,
                    modifier = Modifier.graphicsLayer { alpha = numberAlpha }
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Sign in to continue",
                fontFamily = interFontFamily,
                fontWeight = FontWeight.Normal,
                fontSize = 16.sp,
                color = AppColors.TextSecondary
            )
            Spacer(modifier = Modifier.height(40.dp))

            // Credential Input with gradient wrapper
            GradientFocusWrapper(isGlowing = credFocused) {
                OutlinedTextField(
                    value = credential,
                    onValueChange = { credential = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { credFocused = it.isFocused },
                    placeholder = { 
                        Text("Email, Username, or Phone", color = AppColors.TextSecondary) 
                    },
                    leadingIcon = { 
                        Icon(Icons.Default.Person, contentDescription = null, tint = AppColors.TextSecondary) 
                    },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color.Transparent,
                        unfocusedBorderColor = Color.Transparent,
                        focusedContainerColor = Color(0xFF1A1A1A),
                        unfocusedContainerColor = Color(0xFF1A1A1A),
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                    ),
                    shape = RoundedCornerShape(12.dp)
                )
            }
            Spacer(modifier = Modifier.height(24.dp))

            // Password Input with gradient wrapper
            GradientFocusWrapper(isGlowing = passFocused) {
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { passFocused = it.isFocused },
                    placeholder = { 
                        Text("Password", color = AppColors.TextSecondary) 
                    },
                    leadingIcon = { 
                        Icon(Icons.Default.Lock, contentDescription = null, tint = AppColors.TextSecondary) 
                    },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color.Transparent,
                        unfocusedBorderColor = Color.Transparent,
                        focusedContainerColor = Color(0xFF1A1A1A),
                        unfocusedContainerColor = Color(0xFF1A1A1A),
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                    ),
                    shape = RoundedCornerShape(12.dp)
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
            
            // Sign In Button
            GradientCtaButton(
                text = "Sign In",
                onClick = { onSignIn(credential.trim(), password) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
            )
            Spacer(modifier = Modifier.height(32.dp))

            // Action Links
            Text(
                text = "Forgot Password?",
                modifier = Modifier.clickable {
                    val e = credential.trim()
                    onForgotPassword(e)
                },
                color = AppColors.TextPrimary,
                fontFamily = interFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp
            )
            Spacer(modifier = Modifier.height(16.dp))
            Row {
                Text(
                    "Don't have an account? ",
                    color = AppColors.TextSecondary,
                    fontFamily = interFontFamily,
                    fontSize = 14.sp
                )
                Text(
                    text = "Sign Up",
                    modifier = Modifier.clickable { onSignUp() },
                    color = AppColors.TextPrimary,
                    fontFamily = interFontFamily,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp
                )
            }
        }
    }
}