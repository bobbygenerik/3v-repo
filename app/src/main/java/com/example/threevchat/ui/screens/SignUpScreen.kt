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

private val interFontFamily: FontFamily 
    get() = AppTypography.bodyLarge.fontFamily ?: FontFamily.Default

private val montserratFontFamily: FontFamily 
    get() = AppTypography.displayLarge.fontFamily ?: FontFamily.Default

@Composable
fun SignUpScreen(
    onSignUp: (credential: String, password: String, confirm: String) -> Unit = { _, _, _ -> },
    onBackToSignIn: () -> Unit = {},
    onSendPhoneCode: (phone: String) -> Unit = {},
    onVerifyPhoneCode: (code: String) -> Unit = {}
) {
    var credential by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var smsCode by remember { mutableStateOf("") }
    
    var credFocused by remember { mutableStateOf(false) }
    var passFocused by remember { mutableStateOf(false) }
    var confirmFocused by remember { mutableStateOf(false) }
    
    val looksLikePhone by remember(credential) {
        mutableStateOf(
            credential.trim().let {
                it.startsWith("+") || it.filter { ch -> ch.isDigit() }.length >= 7
            }
        )
    }

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
            .padding(24.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "Create Account",
                fontFamily = montserratFontFamily,
                fontWeight = FontWeight.Bold,
                fontSize = 28.sp,
                color = Color.White
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Get started with your new account",
                fontFamily = interFontFamily,
                fontWeight = FontWeight.Normal,
                fontSize = 16.sp,
                color = AppColors.TextSecondary
            )
            Spacer(modifier = Modifier.height(40.dp))

            GradientFocusWrapper(isGlowing = credFocused) {
                OutlinedTextField(
                    value = credential,
                    onValueChange = { credential = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { credFocused = it.isFocused },
                    placeholder = { Text("Email, Username, or Phone", color = AppColors.TextSecondary) },
                    leadingIcon = { Icon(Icons.Default.Person, contentDescription = null, tint = AppColors.TextSecondary) },
                    singleLine = true,
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

            GradientFocusWrapper(isGlowing = passFocused) {
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { passFocused = it.isFocused },
                    placeholder = { Text("Create Password", color = AppColors.TextSecondary) },
                    leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null, tint = AppColors.TextSecondary) },
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

            GradientFocusWrapper(isGlowing = confirmFocused) {
                OutlinedTextField(
                    value = confirmPassword,
                    onValueChange = { confirmPassword = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { confirmFocused = it.isFocused },
                    placeholder = { Text("Confirm Password", color = AppColors.TextSecondary) },
                    leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null, tint = AppColors.TextSecondary) },
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
            
            GradientCtaButton(
                text = "Sign Up",
                onClick = { onSignUp(credential.trim(), password, confirmPassword) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
            )
            Spacer(modifier = Modifier.height(32.dp))

            if (looksLikePhone) {
                Text(
                    text = "Phone verification",
                    fontFamily = interFontFamily,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    color = AppColors.TextSecondary
                )
                Spacer(Modifier.height(12.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Button(
                        onClick = { onSendPhoneCode(credential.trim()) },
                        enabled = credential.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFF3CB371)
                        )
                    ) { Text("Send Code", color = Color.White) }
                    
                    OutlinedTextField(
                        value = smsCode,
                        onValueChange = { smsCode = it },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("SMS Code", color = AppColors.TextSecondary) },
                        singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color(0xFF3CB371),
                            unfocusedBorderColor = AppColors.InputBorder,
                            focusedContainerColor = Color(0xFF1A1A1A),
                            unfocusedContainerColor = Color(0xFF1A1A1A),
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                    
                    Button(
                        onClick = { onVerifyPhoneCode(smsCode.trim()) },
                        enabled = smsCode.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFF3CB371)
                        )
                    ) { Text("Verify", color = Color.White) }
                }
                Spacer(modifier = Modifier.height(24.dp))
            }

            Row {
                Text(
                    "Already have an account? ",
                    color = AppColors.TextSecondary,
                    fontFamily = interFontFamily,
                    fontSize = 14.sp
                )
                Text(
                    text = "Sign In",
                    modifier = Modifier.clickable { onBackToSignIn() },
                    color = AppColors.TextPrimary,
                    fontFamily = interFontFamily,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp
                )
            }
        }
    }
}