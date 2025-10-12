package com.example.threevchat.viewmodel

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.threevchat.data.UserRepository
import com.example.threevchat.signaling.CallSignalingRepository
import com.example.threevchat.activities.CallActivity
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// --- Data Classes and Enums ---

enum class BannerKind { SUCCESS, ERROR, INFO }
data class BannerMessage(val message: String, val kind: BannerKind)

data class UiState(
    val isLoggedIn: Boolean = false,
    val loading: Boolean = false,
    val error: String? = null,
    val banner: BannerMessage? = null,
    val currentRoom: String? = null,
    val currentRole: String = "caller",
    val needsVerification: Boolean = false,
    val codeSent: Boolean = false,
    val canResendInSec: Int = 0,
    val phoneVerificationInProgress: Boolean = false
)

// --- ViewModel ---

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val userRepo = UserRepository(app)
    private val signaling = CallSignalingRepository()
    private val auth: FirebaseAuth = FirebaseAuth.getInstance()

    private val _ui = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _ui.asStateFlow()

    private val _callLogs = MutableStateFlow<List<Map<String, Any>>>(emptyList())
    val callLogs: StateFlow<List<Map<String, Any>>> = _callLogs.asStateFlow()

    private var incomingJob: Job? = null
    private var pendingUsername: String? = null

    // --- Public Actions ---

    fun queueUsernameClaim(username: String) {
        val uname = username.trim().lowercase()
        if (uname.isNotBlank()) pendingUsername = uname
    }

    fun consumeBanner() {
        _ui.update { it.copy(banner = null) }
    }

    fun fetchCallLogs(userId: String, limit: Long = 20, startAfter: Long? = null) {
        viewModelScope.launch {
            val result = userRepo.getCallLogsForUser(userId, limit, startAfter)
            if (result.isSuccess) {
                _callLogs.value = result.getOrNull() ?: emptyList()
            }
        }
    }

    fun signUpEmail(email: String, password: String) {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            val res = userRepo.registerWithEmail(email, password)
            if (res.isSuccess) {
                _ui.update { it.copy(loading = false, isLoggedIn = true) }
                claimUsernameIfPending()
            } else {
                _ui.update { it.copy(loading = false, error = res.exceptionOrNull()?.message) }
            }
        }
    }

    fun signInEmail(email: String, password: String) {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            val res = userRepo.loginWithEmail(email, password)
            if (res.isSuccess) {
                // Only set isLoggedIn and clear currentRoom, do NOT navigate to call screen
                _ui.update { it.copy(loading = false, isLoggedIn = true, needsVerification = false, currentRoom = null) }
                claimUsernameIfPending()
            } else {
                val msg = res.exceptionOrNull()?.message ?: "Login failed"
                val unverified = msg.contains("verify", ignoreCase = true)
                _ui.update {
                    it.copy(loading = false, error = msg, needsVerification = unverified, isLoggedIn = !unverified)
                }
            }
        }
    }

    fun resendVerification() {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true) }
            val res = userRepo.resendVerificationEmail()
            _ui.update {
                if (res.isSuccess) {
                    it.copy(loading = false, banner = BannerMessage("Verification email sent.", BannerKind.SUCCESS))
                } else {
                    val msg = res.exceptionOrNull()?.message ?: "Failed to resend verification email"
                    it.copy(loading = false, error = msg, banner = BannerMessage(msg, BannerKind.ERROR))
                }
            }
        }
    }

    fun signOut() {
        auth.signOut()
        _ui.value = UiState() // Reset to default state
    }

    fun signInSmart(emailOrUsername: String, password: String) {
        val id = emailOrUsername.trim()
        if (id.contains('@')) {
            signInEmail(id, password)
        } else {
            val isPhoneNumber = id.startsWith("+") || id.count { it.isDigit() } >= 7
            if (!isPhoneNumber) queueUsernameClaim(id)

            viewModelScope.launch {
                _ui.update { it.copy(loading = true, error = null) }
                val res = userRepo.loginWithUsername(id, password)
                if (res.isSuccess) {
                    _ui.update { it.copy(loading = false, isLoggedIn = true, currentRoom = null) }
                    claimUsernameIfPending()
                    // Do NOT set currentRoom except when starting a call
                } else {
                    _ui.update { it.copy(loading = false, error = res.exceptionOrNull()?.message) }
                }
            }
        }
    }

    fun forgotPassword(email: String) {
        val e = email.trim()
        if (e.isBlank() || !e.contains('@')) {
            val errorMsg = "Enter a valid email to reset your password"
            _ui.update { it.copy(error = errorMsg, banner = BannerMessage(errorMsg, BannerKind.ERROR)) }
            return
        }
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            val res = userRepo.sendPasswordResetEmail(e)
            _ui.update {
                if (res.isSuccess) {
                    it.copy(loading = false, banner = BannerMessage("Password reset email sent", BannerKind.SUCCESS))
                } else {
                    val msg = res.exceptionOrNull()?.message
                    it.copy(loading = false, error = msg, banner = msg?.let { BannerMessage(it, BannerKind.ERROR) })
                }
            }
        }
    }

    fun startPhoneVerification(activity: Activity, phone: String) {
        _ui.update { it.copy(loading = true, error = null) }
        userRepo.startPhoneVerification(
            activity,
            phone,
            onError = { msg ->
                _ui.update { it.copy(loading = false, error = msg, phoneVerificationInProgress = false) }
            },
            onCodeSent = {
                _ui.update { it.copy(loading = false, codeSent = true, phoneVerificationInProgress = true) }
                startResendCountdown()
            }
        )
    }

    fun verifySmsCode(code: String) {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            val res = userRepo.verifySmsCode(code)
            if (res.isSuccess) {
                _ui.update { it.copy(loading = false, isLoggedIn = true, phoneVerificationInProgress = false) }
                claimUsernameIfPending()
            } else {
                _ui.update { it.copy(loading = false, error = res.exceptionOrNull()?.message) }
            }
        }
    }

    fun consumeCodeSent() {
        _ui.update { it.copy(codeSent = false) }
    }


    fun resendCode(activity: Activity, phone: String) {
        if (_ui.value.canResendInSec > 0) return
        _ui.update { it.copy(loading = true, error = null) }
        userRepo.startPhoneVerification(
            activity,
            phone,
            onError = { msg ->
                _ui.update { it.copy(loading = false, error = msg) }
            },
            onCodeSent = {
                _ui.update { it.copy(loading = false, codeSent = true) }
                startResendCountdown()
            },
            forceResend = true
        )
    }

    fun startIncomingCallListener() {
        if (incomingJob != null) return
        val user = auth.currentUser ?: return
        val calleePhone = user.phoneNumber
        val calleeUid = user.uid
        val calleeEmail = user.email

        incomingJob = viewModelScope.launch {
            // Listen for direct calls
            launch {
                signaling.listenIncoming(calleePhone, calleeUid, calleeEmail).collect { session ->
                    if (_ui.value.currentRoom != session.id) {
                        _ui.update { it.copy(currentRoom = session.id, currentRole = "callee") }
                    }
                }
            }
            // Listen for invites via different identifiers
            if (!calleePhone.isNullOrBlank()) {
                launch {
                    signaling.listenIncomingParticipantInvites(calleePhone).collect { sid ->
                        if (_ui.value.currentRoom != sid) {
                            _ui.update { it.copy(currentRoom = sid, currentRole = "callee") }
                        }
                    }
                }
            }
            launch {
                signaling.listenIncomingParticipantInvites(calleeUid).collect { sid ->
                    if (_ui.value.currentRoom != sid) {
                        _ui.update { it.copy(currentRoom = sid, currentRole = "callee") }
                    }
                }
            }
            if (!calleeEmail.isNullOrBlank()) {
                launch {
                    signaling.listenIncomingParticipantInvites(calleeEmail).collect { sid ->
                        if (_ui.value.currentRoom != sid) {
                            _ui.update { it.copy(currentRoom = sid, currentRole = "callee") }
                        }
                    }
                }
            }
        }
    }

    fun startCallTo(callee: String) {
        if (callee.isBlank()) {
            Log.w("StartCall", "Attempted to start call without recipient")
            return
        }
        val caller = auth.currentUser?.phoneNumber ?: auth.currentUser?.uid ?: ""
        val sessionId = signaling.createSession(caller = caller, callee = callee)
        _ui.update { it.copy(currentRoom = sessionId, currentRole = "caller") }
    }

    fun launchCall(context: Context, id: String, role: String) {
    val intent = Intent(context, CallActivity::class.java).apply {
            putExtra("sessionId", id)
            putExtra("role", role)
        }
        if (context !is Activity) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun handleIncomingIntent(intent: Intent?) {
        val data = intent?.data ?: return
        when (data.scheme) {
            "tel" -> {
                val number = data.schemeSpecificPart
                if (!number.isNullOrBlank()) startCallTo(number)
            }
            "p2pvideo" -> if (data.host == "call") {
                val sessionId = data.lastPathSegment ?: return
                _ui.update { it.copy(currentRoom = sessionId, currentRole = "callee") }
            }
            "content" -> if (data.host == "com.example.threevchat") {
                val callee = data.lastPathSegment ?: return
                startCallTo(callee)
            }
        }
    }

    fun inviteViaMessages(context: Context, phone: String?) {
        var sessionId = _ui.value.currentRoom
        if (sessionId.isNullOrBlank()) {
            val caller = auth.currentUser?.phoneNumber ?: auth.currentUser?.uid ?: ""
            sessionId = signaling.createSession(caller = caller, callee = phone ?: "")
            _ui.update { it.copy(currentRoom = sessionId, currentRole = "caller") }
        }

        val body = "Join my call: p2pvideo://call/$sessionId"
        val uri = if (!phone.isNullOrBlank()) Uri.parse("smsto:$phone") else Uri.parse("smsto:")
        val intent = Intent(Intent.ACTION_SENDTO, uri).apply { putExtra("sms_body", body) }

        if (context !is Activity) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun openSettings() {
        // This is a no-op navigation hint for the UI layer.
        // The actual navigation is handled by the UI controller (e.g., AppNav).
    }

    // --- Private Helpers ---

    private suspend fun claimUsernameIfPending() {
        val uname = pendingUsername ?: return
        pendingUsername = null // Consume it immediately
        val res = userRepo.claimUsernameForCurrentUser(uname)
        _ui.update {
            if (res.isSuccess) {
                it.copy(banner = BannerMessage("Username '$uname' claimed", BannerKind.SUCCESS))
            } else {
                val msg = res.exceptionOrNull()?.message ?: "Failed to claim username '$uname'"
                it.copy(error = msg, banner = BannerMessage(msg, BannerKind.ERROR))
            }
        }
    }

    private fun startResendCountdown(seconds: Int = 30) {
        viewModelScope.launch {
            for (s in seconds downTo 0) {
                _ui.update { it.copy(canResendInSec = s) }
                delay(1000)
            }
        }
    }
}
