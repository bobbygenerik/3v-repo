package com.example.threevchat

import android.app.Application
import com.google.firebase.FirebaseApp

class P2PApp : Application() {
    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
    }
}
