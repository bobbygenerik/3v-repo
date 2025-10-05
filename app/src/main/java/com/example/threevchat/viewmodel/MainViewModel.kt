package com.example.threevchat.viewmodel

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.threevchat.data.UserRepository
import com.example.threevchat.signaling.CallSignalingRepository
import com.example.threevchat.ui.CallActivity
import com.example.threevchat.BuildConfig
// import com.example.threevchat.util.JitsiRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch


data class UiState(

    val isLoggedIn: Boolean = false,
    val loading: Boolean = false,
    val error: String? = null,
    val currentRoom: String? = null,
    val currentRole: String = "caller", // or "callee"
    val codeSent: Boolean = false,
    val canResendInSec: Int = 0
)

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val userRepo = UserRepository(app)
    // private val jitsiRepo = JitsiRepository(app)
    private val signaling = CallSignalingRepository()

    private val _ui = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _ui

    // Call logs state
    private val _callLogs = MutableStateFlow<List<Map<String, Any>>>(emptyList())
    val callLogs: StateFlow<List<Map<String, Any>>> = _callLogs

    // Incoming call listener job
    private var incomingJob: kotlinx.coroutines.Job? = null

    // Fetch call logs for a user
    fun fetchCallLogs(userId: String, limit: Long = 20, startAfter: Long? = null) {
        viewModelScope.launch {
            val result = userRepo.getCallLogsForUser(userId, limit, startAfter)
            if (result.isSuccess) {
                _callLogs.value = result.getOrNull() ?: emptyList()
            } else {
                // Optionally handle error
            }
        }
    }

    // Username/password flows removed; phone-only auth

    fun startPhoneVerification(activity: Activity, phone: String) {
        _ui.value = _ui.value.copy(loading = true, error = null)
        userRepo.startPhoneVerification(
            activity,
            phone,
            onError = { msg ->
                val friendly = friendlyError(msg)
                Log.e("PhoneAuth", "startPhoneVerification failed: $msg")
                _ui.value = _ui.value.copy(loading = false, error = friendly)
            },
            onCodeSent = {
                _ui.value = _ui.value.copy(loading = false, codeSent = true)
                startResendCountdown()
            }
        )
    }

    fun verifySmsCode(code: String) {
        viewModelScope.launch {
            _ui.value = _ui.value.copy(loading = true, error = null)
            val res = userRepo.verifySmsCode(code)
            _ui.value = if (res.isSuccess) _ui.value.copy(loading = false, isLoggedIn = true) else _ui.value.copy(loading = false, error = res.exceptionOrNull()?.message)
        }
    }

    fun consumeCodeSent() {
        _ui.value = _ui.value.copy(codeSent = false)
    }

    private fun startResendCountdown(seconds: Int = 30) {
        viewModelScope.launch {
            for (s in seconds downTo 0) {
                _ui.value = _ui.value.copy(canResendInSec = s)
                kotlinx.coroutines.delay(1000)
            }
        }
    }

    fun resendCode(activity: Activity, phone: String) {
        if (_ui.value.canResendInSec > 0) return
        _ui.value = _ui.value.copy(loading = true, error = null)
        userRepo.startPhoneVerification(
            activity,
            phone,
            onError = { msg ->
                val friendly = friendlyError(msg)
                Log.e("PhoneAuth", "resendCode failed: $msg")
                _ui.value = _ui.value.copy(loading = false, error = friendly)
            },
            onCodeSent = {
                _ui.value = _ui.value.copy(loading = false, codeSent = true)
                startResendCountdown()
            },
            forceResend = true
        )
    }

    private fun friendlyError(msg: String): String {
        val base = when {
            msg.contains("quota", ignoreCase = true) -> "SMS quota exceeded. Try later or enable billing in Firebase."
            msg.contains("app verification", ignoreCase = true) || msg.contains("recaptcha", ignoreCase = true) ->
                "App verification blocked. Add SHA-256 in Firebase, ensure reCAPTCHA/Play Integrity is configured (or disabled during dev)."
            msg.contains("network", ignoreCase = true) -> "Network error. Check your connection and try again."
            msg.contains("invalid", ignoreCase = true) && msg.contains("phone", ignoreCase = true) -> "Invalid phone number. Use full E.164 format, e.g. +15551234567."
            else -> msg
        }
        return if (BuildConfig.DEBUG) "$base (raw: $msg)" else base
    }

    fun signOut() {
        com.google.firebase.auth.FirebaseAuth.getInstance().signOut()
        _ui.value = UiState() // reset to default
    }

    fun startIncomingCallListener() {
        if (incomingJob != null) return
        val user = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser ?: return
        val calleePhone = user.phoneNumber
        val calleeUid = user.uid
        incomingJob = viewModelScope.launch {
            launch {
                signaling.listenIncoming(calleePhone, calleeUid).collect { session ->
                    if (_ui.value.currentRoom != session.id) {
                        _ui.value = _ui.value.copy(currentRoom = session.id, currentRole = "callee")
                    }
                }
            }
            launch {
                if (!calleePhone.isNullOrBlank()) {
                    signaling.listenIncomingParticipantInvites(calleePhone).collect { sid ->
                        if (_ui.value.currentRoom != sid) {
                            _ui.value = _ui.value.copy(currentRoom = sid, currentRole = "callee")
                        }
                    }
                }
            }
            launch {
                signaling.listenIncomingParticipantInvites(calleeUid).collect { sid ->
                    if (_ui.value.currentRoom != sid) {
                        _ui.value = _ui.value.copy(currentRoom = sid, currentRole = "callee")
                    }
                }
            }
        }
    }

    fun startCallTo(callee: String) {
        // Create a signaling session and store the sessionId in UI state
        val caller = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.phoneNumber
            ?: com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            ?: ""
        val sessionId = signaling.createSession(caller = caller, callee = callee)
        _ui.value = _ui.value.copy(currentRoom = sessionId, currentRole = "caller")
    }

    fun launchCall(context: Context, id: String, role: String) {
        val i = Intent(context, CallActivity::class.java)
            .putExtra("sessionId", id)
            .putExtra("role", role)
        if (context is Activity) context.startActivity(i) else i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).also { context.startActivity(i) }
    }

    fun handleIncomingIntent(intent: Intent) {
        // Parse tel:/custom scheme to create a session if a phone number or id is present
        val data = intent.data ?: return
        val scheme = data.scheme
        if (scheme == "tel") {
            val number = data.schemeSpecificPart
            if (!number.isNullOrBlank()) {
                startCallTo(number)
            }
        } else if (scheme == "p2pvideo" && data.host == "call") {
            // Treat as a sessionId to join as callee
            val sessionId = data.lastPathSegment ?: return
            _ui.value = _ui.value.copy(currentRoom = sessionId, currentRole = "callee")
        } else if (scheme == "content" && data.host == "com.example.threevchat") {
            val callee = data.lastPathSegment ?: return
            startCallTo(callee)
        }
    }

    fun inviteViaMessages(context: Context, phone: String?) {
        // Ensure a session exists
        var sessionId = _ui.value.currentRoom
        if (sessionId.isNullOrBlank()) {
            val caller = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.phoneNumber
                ?: com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
                ?: ""
            // Create a placeholder session targeting provided phone (or empty)
            sessionId = signaling.createSession(caller = caller, callee = phone ?: "")
            _ui.value = _ui.value.copy(currentRoom = sessionId, currentRole = "caller")
        }

        val body = "Join my call: p2pvideo://call/$sessionId"
        val uri = if (!phone.isNullOrBlank()) android.net.Uri.parse("smsto:$phone") else android.net.Uri.parse("smsto:")
        val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
            putExtra("sms_body", body)
        }
        if (context is android.app.Activity) context.startActivity(intent) else intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).also { context.startActivity(intent) }
    }
}
