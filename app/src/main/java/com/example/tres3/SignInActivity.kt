package com.example.tres3

import android.os.Bundle
import android.widget.Toast
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.Image
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import android.content.SharedPreferences
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import com.google.firebase.auth.FirebaseAuth
import android.content.Intent
import com.google.firebase.messaging.FirebaseMessaging
import android.util.Log
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import com.google.firebase.firestore.FirebaseFirestore

class SignInActivity : AppCompatActivity() {

    private lateinit var auth: FirebaseAuth
    private lateinit var sharedPreferences: SharedPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            auth = FirebaseAuth.getInstance()
            sharedPreferences = getSharedPreferences("Tres3Prefs", MODE_PRIVATE)

            if (auth.currentUser != null) {
                navigateToDashboard()
                return
            }

            setContent {
                SignInScreen()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            Toast.makeText(this, "Error initializing app: ${e.message}", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    @Composable
    fun SignInScreen() {
        var email by remember { mutableStateOf("") }
        var password by remember { mutableStateOf("") }
        var passwordVisible by remember { mutableStateOf(false) }
        val keyboardController = LocalSoftwareKeyboardController.current

        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.BackgroundDark)
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Top
        ) {

            Column(
                modifier = Modifier
                    .fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Spacer(modifier = Modifier.height(14.dp))
                Image(
                    painter = painterResource(id = R.drawable.newlogo3),
                    contentDescription = "Tres3 Logo",
                    modifier = Modifier
                        .size(200.dp)
                        .padding(bottom = 0.dp)
                )
                Spacer(modifier = Modifier.height(20.dp))
                Text(
                    text = "Sign in to continue",
                    fontSize = 16.sp,
                    color = AppColors.TextLight,
                    textAlign = TextAlign.Center
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Email input
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email or Phone") },
                leadingIcon = { Icon(Icons.Default.Person, contentDescription = "Person Icon", tint = AppColors.TextLight) },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    imeAction = ImeAction.Next,
                    autoCorrect = false
                ),
                keyboardActions = KeyboardActions(
                    onNext = { /* Focus moves to password automatically */ }
                ),
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = AppColors.PrimaryBlue,
                    unfocusedBorderColor = AppColors.Gray,
                    focusedLabelColor = AppColors.PrimaryBlue,
                    unfocusedLabelColor = AppColors.TextLight,
                    cursorColor = AppColors.PrimaryBlue,
                    focusedContainerColor = AppColors.BackgroundDark,
                    unfocusedContainerColor = AppColors.BackgroundDark,
                    focusedTextColor = AppColors.TextLight,
                    unfocusedTextColor = AppColors.TextLight
                ),
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Password input
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Password") },
                leadingIcon = { Icon(Icons.Default.Lock, contentDescription = "Password Icon", tint = AppColors.TextLight) },
                trailingIcon = {
                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                        Icon(
                            imageVector = if (passwordVisible) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                            contentDescription = if (passwordVisible) "Hide password" else "Show password",
                            tint = AppColors.TextLight
                        )
                    }
                },
                visualTransformation = if (passwordVisible) androidx.compose.ui.text.input.VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                    autoCorrect = false
                ),
                keyboardActions = KeyboardActions(
                    onDone = {
                        keyboardController?.hide()
                        signInWithEmail(email, password)
                    }
                ),
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = AppColors.PrimaryBlue,
                    unfocusedBorderColor = AppColors.Gray,
                    focusedLabelColor = AppColors.PrimaryBlue,
                    unfocusedLabelColor = AppColors.TextLight,
                    cursorColor = AppColors.PrimaryBlue,
                    focusedContainerColor = AppColors.BackgroundDark,
                    unfocusedContainerColor = AppColors.BackgroundDark,
                    focusedTextColor = AppColors.TextLight,
                    unfocusedTextColor = AppColors.TextLight
                ),
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Sign In button
            Button(
                onClick = {
                    signInWithEmail(email, password)
                },
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryBlue),
                modifier = Modifier.fillMaxWidth().height(56.dp)
            ) {
                Text("Sign In")
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Create Account button
            TextButton(onClick = { startActivity(Intent(this@SignInActivity, CreateAccountActivity::class.java)) }) {
                Text("Create Account", color = AppColors.TextLight)
            }

            // Forgot Password
            TextButton(onClick = { resetPassword(email) }) {
                Text("Forgot Password?", color = AppColors.TextLight)
            }
        }
    }

    private fun signInWithEmail(email: String, password: String) {
        if (email.isEmpty() || password.isEmpty()) {
            Toast.makeText(this, "Please fill in all fields", Toast.LENGTH_SHORT).show()
            return
        }
        auth.signInWithEmailAndPassword(email, password)
            .addOnCompleteListener(this) { task ->
                if (task.isSuccessful) {
                    val user = auth.currentUser
                    if (user != null) {
                        saveUserLoginState(user)
                        navigateToDashboard()
                    }
                } else {
                    Toast.makeText(this, "Authentication failed: ${task.exception?.message}",
                        Toast.LENGTH_LONG).show()
                }
            }
    }

    private fun resetPassword(email: String) {
        if (email.isEmpty()) {
            Toast.makeText(this, "Please enter your email first", Toast.LENGTH_SHORT).show()
            return
        }
        auth.sendPasswordResetEmail(email)
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    Toast.makeText(this, "Password reset email sent", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "Failed to send reset email: ${task.exception?.message}",
                        Toast.LENGTH_SHORT).show()
                }
            }
    }

    private fun saveUserLoginState(user: com.google.firebase.auth.FirebaseUser) {
        val sharedPreferences = getSharedPreferences("Tres3Prefs", MODE_PRIVATE)
        val editor = sharedPreferences.edit()
        editor.putBoolean("isLoggedIn", true)
        editor.putString("userId", user.uid)
        editor.putString("userEmail", user.email)
        editor.putString("displayName", user.displayName ?: user.email?.substringBefore("@") ?: "User")
        editor.apply()
    }

    private fun navigateToDashboard() {
        Log.d("SignIn", "🔄 Updating FCM token before navigating to HomeActivity...")
        
        lifecycleScope.launch {
            try {
                val token = FirebaseMessaging.getInstance().token.await()
                val user = auth.currentUser
                
                if (user != null && token != null) {
                    Log.d("SignIn", "📱 Got FCM token: ${token.take(20)}...")
                    
                    FirebaseFirestore.getInstance()
                        .collection("users")
                        .document(user.uid)
                        .update(
                            mapOf(
                                "fcmToken" to token,
                                "tokenLastUpdated" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                            )
                        )
                        .await()
                    
                    Log.d("SignIn", "✅ FCM token updated successfully before navigation")
                } else {
                    Log.w("SignIn", "⚠️ No user or token available")
                }
            } catch (e: Exception) {
                Log.e("SignIn", "❌ Failed to update FCM token: ${e.message}")
                // Continue anyway - HomeActivity will retry
            }
            
            startActivity(Intent(this@SignInActivity, HomeActivity::class.java))
            finish()
        }
    }
}