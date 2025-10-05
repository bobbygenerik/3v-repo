package com.example.threevchat

import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth

class P2PApp : Application() {
    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)

        // Debug-only: bypass app verification (reCAPTCHA/Play Integrity) for Phone Auth.
        // This should NEVER be enabled in release builds.
        // Use test phone numbers in Firebase Console to avoid sending real SMS during development.
        if (BuildConfig.DEBUG) {
            runCatching {
                FirebaseAuth.getInstance().firebaseAuthSettings.setAppVerificationDisabledForTesting(true)
            }
        }
    }
}
