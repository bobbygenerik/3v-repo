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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextFieldDefaults
import com.google.firebase.auth.FirebaseAuth
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.google.firebase.messaging.FirebaseMessaging
import android.util.Log
import kotlinx.coroutines.tasks.await
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class CreateAccountActivity : AppCompatActivity() {

    private lateinit var auth: FirebaseAuth

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        auth = FirebaseAuth.getInstance()

        setContent {
            CreateAccountScreen()
        }
    }

    @Composable
    fun CreateAccountScreen() {
        var email by remember { mutableStateOf("") }
        var password by remember { mutableStateOf("") }
        var confirmPassword by remember { mutableStateOf("") }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.BackgroundDark)
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Top
        ) {
            Spacer(modifier = Modifier.height(14.dp))

            // Logo
            Image(
                painter = painterResource(id = R.drawable.newlogo3),
                contentDescription = "Tres3 Logo",
                modifier = Modifier
                    .size(200.dp)
                    .padding(bottom = 0.dp)
            )

            Spacer(modifier = Modifier.height(20.dp))

            // Title - moved up 20px with spacer above
            Text(
                text = "Get started with your new account",
                fontSize = 16.sp,
                color = AppColors.TextLight
            )

            Spacer(modifier = Modifier.height(20.dp))

            // Email or Phone input
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email or phone number") },
                placeholder = { Text("your@email.com or +1234567890") },
                leadingIcon = { Icon(Icons.Default.Person, contentDescription = "Email/Phone Icon", tint = AppColors.TextLight) },
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

            // Password input
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Password") },
                leadingIcon = { Icon(Icons.Default.Lock, contentDescription = "Password Icon", tint = AppColors.TextLight) },
                visualTransformation = PasswordVisualTransformation(),
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

            // Confirm Password field
            OutlinedTextField(
                value = confirmPassword,
                onValueChange = { confirmPassword = it },
                label = { Text("Confirm Password") },
                leadingIcon = { Icon(Icons.Default.Lock, contentDescription = "Confirm Password Icon", tint = AppColors.TextLight) },
                visualTransformation = PasswordVisualTransformation(),
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

            // Create Account button
            Button(
                onClick = { createAccount(email, password, confirmPassword) },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryBlue)
            ) {
                Text("Create Account")
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Back to Sign In
            TextButton(onClick = { finish() }) {
                Text("Already have an account? Sign In", color = AppColors.TextLight)
            }
        }
    }

    private fun createAccount(email: String, password: String, confirmPassword: String) {
        if (email.isEmpty() || password.isEmpty()) {
            Toast.makeText(this, "Please fill all fields", Toast.LENGTH_SHORT).show()
            return
        }

        if (password != confirmPassword) {
            Toast.makeText(this, "Passwords do not match", Toast.LENGTH_SHORT).show()
            return
        }

        // Proceed with account creation
        createFirebaseAccount(email, password)
    }

    private fun createFirebaseAccount(email: String, password: String) {
        FirebaseAuth.getInstance().createUserWithEmailAndPassword(email, password)
            .addOnCompleteListener(this) { task ->
                if (task.isSuccessful) {
                    val user = FirebaseAuth.getInstance().currentUser
                    
                    user?.let {
                        // Get FCM token immediately and save with user data
                        Log.d("CreateAccount", "🔄 Getting FCM token for new user...")
                        
                        FirebaseMessaging.getInstance().token
                            .addOnSuccessListener { token ->
                                Log.d("CreateAccount", "✅ FCM token obtained: ${token.take(20)}...")
                                saveUserDataWithToken(it.uid, email, token)
                            }
                            .addOnFailureListener { e ->
                                Log.e("CreateAccount", "❌ Failed to get FCM token: ${e.message}")
                                // Save without token - will be added when user signs in
                                saveUserDataWithToken(it.uid, email, null)
                            }
                    }
                } else {
                    Toast.makeText(this, "Account creation failed: ${task.exception?.message}", Toast.LENGTH_SHORT).show()
                }
            }
    }
    
    private fun saveUserDataWithToken(uid: String, email: String, fcmToken: String?) {
        val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
        val displayName = email.substringBefore("@")
        
        val userData = hashMapOf(
            "email" to email,
            "displayName" to displayName,
            "isOnline" to false,
            "createdAt" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
            "fcmToken" to (fcmToken ?: ""),
            "tokenLastUpdated" to com.google.firebase.firestore.FieldValue.serverTimestamp()
        )
        
        Log.d("CreateAccount", "💾 Saving user data with FCM token...")
        
        db.collection("users")
            .document(uid)
            .set(userData)
            .addOnSuccessListener {
                Log.d("CreateAccount", "✅ User profile saved successfully")
                
                // Send verification email
                val user = FirebaseAuth.getInstance().currentUser
                user?.sendEmailVerification()
                    ?.addOnCompleteListener { verificationTask ->
                        if (verificationTask.isSuccessful) {
                            Toast.makeText(this, "Account created! Please check your email to verify.", Toast.LENGTH_LONG).show()
                            finish()
                        } else {
                            Toast.makeText(this, "Account created but failed to send verification email", Toast.LENGTH_SHORT).show()
                            finish()
                        }
                    }
            }
            .addOnFailureListener { e ->
                Log.e("CreateAccount", "❌ Failed to save user profile: ${e.message}")
                Toast.makeText(this, "Account created but failed to save profile: ${e.message}", Toast.LENGTH_SHORT).show()
                finish()
            }
    }
}