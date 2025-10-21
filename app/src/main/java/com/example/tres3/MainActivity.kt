package com.example.tres3

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.google.firebase.auth.FirebaseAuth

class MainActivity : AppCompatActivity() {

    private lateinit var auth: FirebaseAuth

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        auth = FirebaseAuth.getInstance()

        // Check if user is already signed in with Firebase Auth
        if (auth.currentUser != null) {
            // User is authenticated, go to home screen
            startActivity(Intent(this, HomeActivity::class.java))
        } else {
            // User not authenticated, go to splash screen
            startActivity(Intent(this, SplashActivity::class.java))
        }

        finish() // Close this activity
    }
}