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
    private val storage by lazy { com.google.firebase.storage.FirebaseStorage.getInstance() }

    private var verificationId: String? = null
    private var resendingToken: PhoneAuthProvider.ForceResendingToken? = null

    // Username/password (email) auth
    suspend fun registerWithEmail(email: String, password: String): Result<Unit> {
        return try {
            // Use device language for auth-related flows
            try { auth.useAppLanguage() } catch (_: Throwable) {}
            auth.createUserWithEmailAndPassword(email, password).await()
            val userId = auth.currentUser?.uid
            // Send verification email
            try { auth.currentUser?.sendEmailVerification()?.await() } catch (_: Exception) {}
            val profile = mapOf(
                "email" to email,
                "createdAt" to com.google.firebase.Timestamp.now()
            )
            if (userId != null) {
                db.collection("users").document(userId).set(profile)
            }
            Result.success(Unit)
        } catch (e: Exception) {
            val friendly = when ((e as? FirebaseAuthException)?.errorCode) {
                "ERROR_OPERATION_NOT_ALLOWED" -> "Email/Password is disabled. Enable it in Firebase Console → Authentication → Sign-in method."
                "ERROR_WEAK_PASSWORD" -> "Password is too weak. Use at least 6 characters."
                "ERROR_EMAIL_ALREADY_IN_USE" -> "An account with this email already exists."
                "ERROR_INVALID_EMAIL" -> "Invalid email address."
                else -> e.message ?: "Registration failed"
            }
            Result.failure(Exception(friendly, e))
        }
    }

    suspend fun loginWithEmail(email: String, password: String): Result<Unit> {
        return try {
            try { auth.useAppLanguage() } catch (_: Throwable) {}
            auth.signInWithEmailAndPassword(email, password).await()
            val user = auth.currentUser
            if (user != null && !user.isEmailVerified) {
                // Keep user signed in but report not-verified so UI can gate access
                Result.failure(IllegalStateException("Please verify your email before signing in."))
            } else {
                Result.success(Unit)
            }
        } catch (e: Exception) {
            val friendly = when ((e as? FirebaseAuthException)?.errorCode) {
                "ERROR_OPERATION_NOT_ALLOWED" -> "Email/Password is disabled. Enable it in Firebase Console → Authentication → Sign-in method."
                "ERROR_USER_DISABLED" -> "This account has been disabled."
                "ERROR_USER_NOT_FOUND" -> "No account found for this email."
                "ERROR_WRONG_PASSWORD" -> "Incorrect password."
                "ERROR_INVALID_EMAIL" -> "Invalid email address."
                else -> e.message ?: "Login failed"
            }
            Result.failure(Exception(friendly, e))
        }
    }

    suspend fun resendVerificationEmail(): Result<Unit> {
        val user = auth.currentUser
        return if (user != null && !user.isEmailVerified) {
            try {
                user.sendEmailVerification().await()
                Result.success(Unit)
            } catch (e: Exception) {
                Result.failure(e)
            }
        } else if (user == null) {
            Result.failure(IllegalStateException("No user is signed in."))
        } else {
            Result.failure(IllegalStateException("Email is already verified."))
        }
    }

    suspend fun sendPasswordResetEmail(email: String): Result<Unit> {
        return try {
            try { auth.useAppLanguage() } catch (_: Throwable) {}
            auth.sendPasswordResetEmail(email).await()
            Result.success(Unit)
        } catch (e: Exception) {
            val friendly = when ((e as? FirebaseAuthException)?.errorCode) {
                "ERROR_INVALID_EMAIL" -> "Invalid email address."
                "ERROR_USER_NOT_FOUND" -> "No account found for this email."
                else -> e.message ?: "Failed to send reset email"
            }
            Result.failure(Exception(friendly, e))
        }
    }

    // ---- Username support (Firestore mapping) ----
    // usernames/{username} -> { uid, email }
    suspend fun claimUsernameForCurrentUser(username: String): Result<Unit> {
        val user = auth.currentUser ?: return Result.failure(IllegalStateException("Not signed in"))
        val uname = username.trim().lowercase()
        if (uname.isBlank()) return Result.failure(IllegalArgumentException("Username cannot be blank"))
        return try {
            db.runTransaction { tx ->
                val ref = db.collection("usernames").document(uname)
                val snap = tx.get(ref)
                if (snap.exists()) throw IllegalStateException("Username is already taken")
                val data = mapOf("uid" to user.uid, "email" to (user.email ?: ""))
                tx.set(ref, data)
                // Also store on user profile
                tx.update(db.collection("users").document(user.uid), mapOf("username" to uname))
            }.await()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun loginWithUsername(username: String, password: String): Result<Unit> {
        val uname = username.trim().lowercase()
        if (uname.isBlank()) return Result.failure(IllegalArgumentException("Enter a username"))
        return try {
            val snap = db.collection("usernames").document(uname).get().await()
            val email = (snap.data?.get("email") as? String)?.takeIf { it.isNotBlank() }
            if (email == null) return Result.failure(IllegalStateException("Username not found"))
            loginWithEmail(email, password)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

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

    // ---- Profile management ----
    data class UserProfile(
        val uid: String,
        val email: String?,
        val username: String?,
        val displayName: String?,
        val bio: String?,
        val photoUrl: String?
    )

    suspend fun getProfile(): Result<UserProfile> {
        val user = auth.currentUser ?: return Result.failure(IllegalStateException("Not signed in"))
        return try {
            val snap = db.collection("users").document(user.uid).get().await()
            val data = snap.data ?: emptyMap()
            val profile = UserProfile(
                uid = user.uid,
                email = user.email,
                username = data["username"] as? String,
                displayName = data["displayName"] as? String,
                bio = data["bio"] as? String,
                photoUrl = data["photoUrl"] as? String
            )
            Result.success(profile)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun updateProfile(displayName: String?, bio: String?): Result<Unit> {
        val user = auth.currentUser ?: return Result.failure(IllegalStateException("Not signed in"))
        return try {
            val update = mutableMapOf<String, Any>()
            displayName?.let { update["displayName"] = it }
            bio?.let { update["bio"] = it }
            if (update.isNotEmpty()) {
                db.collection("users").document(user.uid).set(update, com.google.firebase.firestore.SetOptions.merge()).await()
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun uploadProfilePhoto(contentUri: android.net.Uri): Result<String> {
        val user = auth.currentUser ?: return Result.failure(IllegalStateException("Not signed in"))
        return try {
            // Always write to a concrete path; Storage will create the object if it does not exist
            val ref = storage.reference
                .child("profile_photos")
                .child("${user.uid}.jpg")

            // Try to determine content type for better caching/preview in Storage console
            val contentResolver = app.contentResolver
            val mime = runCatching { contentResolver.getType(contentUri) }.getOrNull() ?: "image/jpeg"
            val metadata = com.google.firebase.storage.StorageMetadata.Builder()
                .setContentType(mime)
                .build()

            // Upload file with metadata. Do not pre-delete to avoid transient not-found errors.
            ref.putFile(contentUri, metadata).await()
            val url = ref.downloadUrl.await().toString()
            db.collection("users").document(user.uid)
                .set(mapOf("photoUrl" to url), com.google.firebase.firestore.SetOptions.merge())
                .await()
            Result.success(url)
        } catch (e: Exception) {
            // Provide clearer errors
            val friendly = if (e is com.google.firebase.storage.StorageException) {
                when (e.errorCode) {
                    com.google.firebase.storage.StorageException.ERROR_OBJECT_NOT_FOUND -> "Storage path not found. Check Firebase Storage rules and bucket configuration."
                    com.google.firebase.storage.StorageException.ERROR_NOT_AUTHORIZED -> "Not authorized to upload. Check Firebase Storage rules."
                    com.google.firebase.storage.StorageException.ERROR_QUOTA_EXCEEDED -> "Storage quota exceeded."
                    else -> e.message ?: "Upload failed"
                }
            } else e.message ?: "Upload failed"
            Result.failure(Exception(friendly, e))
        }
    }
}
