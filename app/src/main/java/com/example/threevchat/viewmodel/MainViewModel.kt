package com.example.threevchat.viewmodel

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.threevchat.data.UserRepository
import com.example.threevchat.util.JitsiRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch


data class UiState(

    val isLoggedIn: Boolean = false,
    val loading: Boolean = false,
    val error: String? = null,
    val currentRoom: String? = null
)

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val userRepo = UserRepository(app)
    private val jitsiRepo = JitsiRepository(app)

    private val _ui = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _ui

    // Call logs state
    private val _callLogs = MutableStateFlow<List<Map<String, Any>>>(emptyList())
    val callLogs: StateFlow<List<Map<String, Any>>> = _callLogs

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

    fun registerWithUsername(username: String, password: String) {
        viewModelScope.launch {
            _ui.value = _ui.value.copy(loading = true, error = null)
            val res = userRepo.registerWithUsername(username, password)
            _ui.value = if (res.isSuccess) _ui.value.copy(loading = false, isLoggedIn = true) else _ui.value.copy(loading = false, error = res.exceptionOrNull()?.message)
        }
    }

    fun loginWithUsername(username: String, password: String) {
        viewModelScope.launch {
            _ui.value = _ui.value.copy(loading = true, error = null)
            val res = userRepo.loginWithUsername(username, password)
            _ui.value = if (res.isSuccess) _ui.value.copy(loading = false, isLoggedIn = true) else _ui.value.copy(loading = false, error = res.exceptionOrNull()?.message)
        }
    }

    fun startPhoneVerification(activity: Activity, phone: String) {
        userRepo.startPhoneVerification(activity, phone)
    }

    fun verifySmsCode(code: String) {
        viewModelScope.launch {
            _ui.value = _ui.value.copy(loading = true, error = null)
            val res = userRepo.verifySmsCode(code)
            _ui.value = if (res.isSuccess) _ui.value.copy(loading = false, isLoggedIn = true) else _ui.value.copy(loading = false, error = res.exceptionOrNull()?.message)
        }
    }

    fun startCallTo(callee: String) {
        val room = jitsiRepo.buildRoomNameForCallee(callee)
        _ui.value = _ui.value.copy(currentRoom = room)
    }

    fun launchJitsiCall(context: Context, room: String) {
        jitsiRepo.launchJitsi(context, room)
    }

    fun handleIncomingIntent(intent: Intent) {
        val parsed = jitsiRepo.parseCallIntent(intent)
        parsed?.let {
            _ui.value = _ui.value.copy(currentRoom = it)
        }
    }
}
