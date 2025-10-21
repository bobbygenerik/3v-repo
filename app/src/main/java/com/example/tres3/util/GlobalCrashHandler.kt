package com.example.tres3.util

import android.content.Context
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import timber.log.Timber
import java.io.PrintWriter
import java.io.StringWriter

class GlobalCrashHandler(
    private val applicationContext: Context,
    private val defaultHandler: Thread.UncaughtExceptionHandler?
) : Thread.UncaughtExceptionHandler {

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        Timber.tag("GlobalCrashHandler").e(throwable, "FATAL EXCEPTION in thread ${thread.name}")

        // Log the crash to Firestore for remote debugging
        logCrashToFirestore(throwable)

        // Finally, delegate to the default handler to terminate the app
        defaultHandler?.uncaughtException(thread, throwable)
    }

    private fun logCrashToFirestore(throwable: Throwable) {
        try {
            val auth = FirebaseAuth.getInstance()
            val currentUser = auth.currentUser

            // We can only log if a user is signed in
            if (currentUser != null) {
                val db = FirebaseFirestore.getInstance()
                val stackTrace = StringWriter().also {
                    throwable.printStackTrace(PrintWriter(it))
                }.toString()

                val crashReport = hashMapOf(
                    "userId" to currentUser.uid,
                    "email" to (currentUser.email ?: "N/A"),
                    "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                    "message" to (throwable.message ?: "No message"),
                    "exceptionType" to throwable.javaClass.name,
                    "stackTrace" to stackTrace.take(10000) // Limit stack trace size
                )

                db.collection("crashes")
                  .add(crashReport)
                  .addOnSuccessListener { Timber.tag("GlobalCrashHandler").d("Successfully logged crash to Firestore.") }
                  .addOnFailureListener { e -> Timber.tag("GlobalCrashHandler").e(e, "Failed to log crash to Firestore.") }
            }
        } catch (e: Exception) {
            Timber.tag("GlobalCrashHandler").e(e, "Error while trying to log crash to Firestore.")
        }
    }

    companion object {
        fun setup(applicationContext: Context) {
            val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
            if (defaultHandler !is GlobalCrashHandler) {
                Thread.setDefaultUncaughtExceptionHandler(
                    GlobalCrashHandler(applicationContext, defaultHandler)
                )
                Timber.tag("GlobalCrashHandler").d("Global crash handler has been set up.")
            }
        }
    }
}
