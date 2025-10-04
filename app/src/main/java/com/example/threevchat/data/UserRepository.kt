package com.example.threevchat.data

import android.app.Activity
import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseException
import com.google.firebase.auth.FirebaseAuth
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
            Result.failure(e)
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
            Result.failure(e)
        }
    }

    fun startPhoneVerification(activity: Activity, phone: String) {
        val callbacks = object : PhoneAuthProvider.OnVerificationStateChangedCallbacks() {
            override fun onVerificationCompleted(credential: PhoneAuthCredential) {
                Log.d("Auth", "Auto verification completed")
            }
            override fun onVerificationFailed(e: FirebaseException) {
                Log.e("Auth", "Verification failed", e)
            }
            override fun onCodeSent(verificationId: String, token: PhoneAuthProvider.ForceResendingToken) {
                this@UserRepository.verificationId = verificationId
                Log.d("Auth", "Code sent: $verificationId")
            }
        }
        val options = PhoneAuthOptions.newBuilder(auth)
            .setPhoneNumber(phone)
            .setTimeout(60L, TimeUnit.SECONDS)
            .setActivity(activity)
            .setCallbacks(callbacks)
            .build()
        PhoneAuthProvider.verifyPhoneNumber(options)
    }

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
