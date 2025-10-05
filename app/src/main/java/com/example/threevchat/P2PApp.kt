package com.example.threevchat

import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth

class P2PApp : Application() {
    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)

        // Optional: bypass app verification for testing (controlled via local.properties)
        if (BuildConfig.PHONE_AUTH_DISABLE_APP_VERIFICATION) {
            runCatching {
                FirebaseAuth.getInstance().firebaseAuthSettings.setAppVerificationDisabledForTesting(true)
            }
        }
    }
}
