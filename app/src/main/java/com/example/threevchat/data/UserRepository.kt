package com.example.threevchat.data

import android.app.Activity
import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.PhoneAuthCredential
import com.google.firebase.auth.PhoneAuthOptions
import com.google.firebase.auth.PhoneAuthProvider
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await
import java.util.concurrent.TimeUnit

class UserRepository(private val app: Application) {
    private val auth: FirebaseAuth = FirebaseAuth.getInstance()
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance()

    private var verificationId: String? = null
    private var resendingToken: PhoneAuthProvider.ForceResendingToken? = null

    /* Username/password registration removed (phone-only auth)
    suspend fun registerWithUsername(username: String, password: String): Result<Unit> {
        return try {
            auth.createUserWithEmailAndPassword(username, password).await()
            val userId = auth.currentUser?.uid
            val email = auth.currentUser?.email
            val userProfile = mapOf(
                "username" to username,
                "email" to email,
                "avatarUrl" to "" // or a default value
            )
            if (userId != null) {
                db.collection("users").document(userId).set(userProfile)
            }
            Result.success(Unit)
        } catch (e: Exception) {
            val friendly = when ((e as? FirebaseAuthException)?.errorCode) {
                // Common when Email/Password is disabled in Firebase Console
                "ERROR_OPERATION_NOT_ALLOWED" -> "Email/Password sign-in is disabled. Enable it in Firebase Console → Authentication → Sign-in method."
                else -> e.message ?: "Registration failed"
            }
            Result.failure(Exception(friendly, e))
        }
    }

    suspend fun loginWithUsername(username: String, password: String): Result<Unit> {
        return try {
            auth.signInWithEmailAndPassword(username, password).await()
            val userId = auth.currentUser?.uid
            val email = auth.currentUser?.email
            val userProfile = mapOf(
                "username" to username,
                "email" to email,
                "avatarUrl" to "" // or a default value
            )
            if (userId != null) {
                db.collection("users").document(userId).set(userProfile)
            }
            Result.success(Unit)
        } catch (e: Exception) {
            val friendly = when ((e as? FirebaseAuthException)?.errorCode) {
                "ERROR_OPERATION_NOT_ALLOWED" -> "Email/Password sign-in is disabled. Enable it in Firebase Console → Authentication → Sign-in method."
                "ERROR_USER_DISABLED" -> "This account has been disabled."
                "ERROR_USER_NOT_FOUND" -> "No account found for this username."
                "ERROR_WRONG_PASSWORD" -> "Incorrect password."
                else -> e.message ?: "Login failed"
            }
            Result.failure(Exception(friendly, e))
        }
    }
    */

    fun startPhoneVerification(
        activity: Activity,
        phone: String,
        onError: (String) -> Unit = {},
        onCodeSent: () -> Unit = {},
        forceResend: Boolean = false
    ) {
        // During development, you can disable app verification to allow code sending without Play Integrity on emulators/devices.
        // Make sure to NOT ship with this enabled.
        try {
            val disable = com.example.threevchat.BuildConfig.PHONE_AUTH_DISABLE_APP_VERIFICATION
            if (disable) {
                FirebaseAuth.getInstance().firebaseAuthSettings.forceRecaptchaFlowForTesting(false)
                FirebaseAuth.getInstance().firebaseAuthSettings.setAppVerificationDisabledForTesting(true)
                Log.w("Auth", "App verification DISABLED for testing (do not enable in production)")
            }
        } catch (t: Throwable) {
            Log.w("Auth", "Unable to adjust FirebaseAuthSettings: ${t.message}")
        }
        val callbacks = object : PhoneAuthProvider.OnVerificationStateChangedCallbacks() {
            override fun onVerificationCompleted(credential: PhoneAuthCredential) {
                Log.d("Auth", "Auto verification completed")
            }
            override fun onVerificationFailed(e: FirebaseException) {
                Log.e("Auth", "Verification failed", e)
                val detail = e.localizedMessage ?: e.message ?: "Phone verification failed"
                onError("${e::class.java.simpleName}: $detail")
            }
            override fun onCodeSent(verificationId: String, token: PhoneAuthProvider.ForceResendingToken) {
                this@UserRepository.verificationId = verificationId
                this@UserRepository.resendingToken = token
                Log.d("Auth", "Code sent: $verificationId")
                onCodeSent()
            }
        }
        val builder = PhoneAuthOptions.newBuilder(auth)
            .setPhoneNumber(phone)
            .setTimeout(60L, TimeUnit.SECONDS)
            .setActivity(activity)
            .setCallbacks(callbacks)
        if (forceResend) {
            resendingToken?.let { builder.setForceResendingToken(it) }
        }
        try {
            PhoneAuthProvider.verifyPhoneNumber(builder.build())
        } catch (t: Throwable) {
            onError("PhoneAuth start failed: ${t.message}")
        }
    }

    fun hasResendToken(): Boolean = resendingToken != null

    suspend fun verifySmsCode(code: String): Result<Unit> {
        val id = verificationId ?: return Result.failure(IllegalStateException("No verification id"))
        return try {
            val credential = PhoneAuthProvider.getCredential(id, code)
            auth.signInWithCredential(credential).await()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // --- Call Log Firestore Integration ---
    suspend fun saveCallLog(callerId: String, calleeId: String, startedAt: Long, durationSeconds: Int): Result<Unit> {
        val callLog = hashMapOf(
            "callerId" to callerId,
            "calleeId" to calleeId,
            "startedAt" to startedAt,
            "durationSeconds" to durationSeconds
        )
        return try {
            db.collection("calls").add(callLog).await()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getCallLogsForUser(userId: String, limit: Long = 20, startAfter: Long? = null): Result<List<Map<String, Any>>> {
        return try {
            var query = db.collection("calls")
                .whereEqualTo("callerId", userId)
                .orderBy("startedAt", com.google.firebase.firestore.Query.Direction.DESCENDING)
                .limit(limit)
            if (startAfter != null) {
                query = query.startAfter(startAfter)
            }
            val snapshot = query.get().await()
            val logs = snapshot.documents.mapNotNull { it.data }
            Result.success(logs)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun saveChatMessage(roomId: String, senderId: String, text: String) {
        val message = mapOf(
            "senderId" to senderId,
            "text" to text,
            "timestamp" to com.google.firebase.Timestamp.now()
        )
        db.collection("rooms").document(roomId)
            .collection("messages")
            .add(message)
    }
}
