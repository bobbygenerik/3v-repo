package com.example.tres3

import android.app.Application
import io.livekit.android.room.Room
import timber.log.Timber

class Tres3Application : Application() {
    var room: Room? = null

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }

        // Initialize feature flags system for enhancement management
        FeatureFlags.init(this)

        // Global crash handler to capture uncaught exceptions when logs are hard to access
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                Timber.e(throwable, "Uncaught exception in thread %s", thread.name)
                // Best-effort: write a lightweight crash marker to Firestore if user is signed in
                try {
                    val auth = com.google.firebase.auth.FirebaseAuth.getInstance()
                    val user = auth.currentUser
                    if (user != null) {
                        val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                        val crashData = hashMapOf(
                            "timestamp" to com.google.firebase.Timestamp.now(),
                            "thread" to thread.name,
                            "message" to (throwable.message ?: "<no message>"),
                            "type" to throwable.javaClass.name,
                        )
                        db.collection("users")
                            .document(user.uid)
                            .collection("crashReports")
                            .add(crashData)
                    }
                } catch (_: Exception) { /* ignore secondary failures */ }
            } catch (_: Exception) {
                // ignore logging failures
            } finally {
                // Delegate to system/default handler after logging
                defaultHandler?.uncaughtException(thread, throwable)
            }
        }
    }
}