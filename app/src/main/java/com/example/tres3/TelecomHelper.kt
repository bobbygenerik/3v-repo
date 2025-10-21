package com.example.tres3

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.getSystemService

/**
 * Helper for managing Android Telecom system integration
 * Handles phone account registration and call launching
 */
object TelecomHelper {
    
    private const val TAG = "TelecomHelper"
    private const val PHONE_ACCOUNT_ID = "Tres3VideoCall"
    private const val PHONE_ACCOUNT_LABEL = "Tres3"
    
    /**
     * Register phone account with Android system
     * Must be called before making or receiving calls
     */
    fun registerPhoneAccount(context: Context): PhoneAccountHandle? {
        val telecomManager = context.getSystemService<TelecomManager>() ?: run {
            Log.e(TAG, "❌ TelecomManager not available")
            return null
        }
        
        val componentName = ComponentName(context, Tres3ConnectionService::class.java)
        val phoneAccountHandle = PhoneAccountHandle(componentName, PHONE_ACCOUNT_ID)
        
        val phoneAccount = PhoneAccount.builder(phoneAccountHandle, PHONE_ACCOUNT_LABEL)
            .setCapabilities(
                PhoneAccount.CAPABILITY_VIDEO_CALLING or
                PhoneAccount.CAPABILITY_CALL_PROVIDER or
                PhoneAccount.CAPABILITY_SELF_MANAGED
            )
            .setHighlightColor(0xFF2E7D32.toInt()) // Green color
            .setSupportedUriSchemes(listOf(PhoneAccount.SCHEME_SIP, PhoneAccount.SCHEME_TEL))
            .build()
        
        try {
            telecomManager.registerPhoneAccount(phoneAccount)
            Log.d(TAG, "✅ Phone account registered successfully")
            return phoneAccountHandle
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to register phone account", e)
            return null
        }
    }
    
    /**
     * Check if phone account is registered
     */
    fun isPhoneAccountRegistered(context: Context): Boolean {
        val telecomManager = context.getSystemService<TelecomManager>() ?: return false
        val phoneAccountHandle = getPhoneAccountHandle(context)
        
        return telecomManager.getPhoneAccount(phoneAccountHandle) != null
    }
    
    /**
     * Get the phone account handle for this app
     */
    fun getPhoneAccountHandle(context: Context): PhoneAccountHandle {
        val componentName = ComponentName(context, Tres3ConnectionService::class.java)
        return PhoneAccountHandle(componentName, PHONE_ACCOUNT_ID)
    }
    
    /**
     * Start an outgoing call using native Android UI
     * This will show Android's native call screen with animations
     */
    fun startOutgoingCall(
        context: Context,
        contactName: String,
        contactId: String,
        roomName: String,
        url: String,
        token: String
    ): Boolean {
        val telecomManager = context.getSystemService<TelecomManager>() ?: run {
            Log.e(TAG, "❌ TelecomManager not available")
            return false
        }
        
        val phoneAccountHandle = getPhoneAccountHandle(context)
        
        // Create extras bundle with call data
        val extras = Bundle().apply {
            putString("contactName", contactName)
            putString("contactId", contactId)
            putString("roomName", roomName)
            putString("url", url)
            putString("token", token)
            putInt(TelecomManager.EXTRA_START_CALL_WITH_VIDEO_STATE, VideoProfile.STATE_BIDIRECTIONAL)
        }
        
        // Create address (can be contact ID or formatted number)
        val address = Uri.fromParts(PhoneAccount.SCHEME_SIP, contactId, null)
        
        try {
            if (context.checkSelfPermission(android.Manifest.permission.CALL_PHONE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "❌ Missing CALL_PHONE permission")
                // Optionally, you could request the permission here
                return false
            }
            // This launches Android's native outgoing call UI
            telecomManager.placeCall(address, extras.apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccountHandle)
            })
            
            Log.d(TAG, "📞 Outgoing call initiated via Telecom: $contactName")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to place call", e)
            return false
        }
    }
    
    /**
     * Show incoming call using native Android UI
     * This will show Android's native incoming call screen with animations
     */
    fun showIncomingCall(
        context: Context,
        callerName: String,
        callerId: String,
        invitationId: String,
        roomName: String,
        url: String,
        token: String
    ): Boolean {
        val telecomManager = context.getSystemService<TelecomManager>() ?: run {
            Log.e(TAG, "❌ TelecomManager not available")
            return false
        }
        
        val phoneAccountHandle = getPhoneAccountHandle(context)
        
        // Create extras bundle with call data
        val extras = Bundle().apply {
            putString("callerName", callerName)
            putString("callerId", callerId)
            putString("invitationId", invitationId)
            putString("roomName", roomName)
            putString("url", url)
            putString("token", token)
            putInt(TelecomManager.EXTRA_INCOMING_VIDEO_STATE, VideoProfile.STATE_BIDIRECTIONAL)
        }
        
        // Create address
        val address = Uri.fromParts(PhoneAccount.SCHEME_SIP, callerId, null)
        
        try {
            // This triggers Android's native incoming call UI
            telecomManager.addNewIncomingCall(phoneAccountHandle, extras.apply {
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, address)
            })
            
            Log.d(TAG, "📱 Incoming call displayed via Telecom: $callerName")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to show incoming call", e)
            return false
        }
    }
    
    /**
     * End an active call
     */
    fun endCall(roomName: String) {
        val connection = Tres3ConnectionService.getActiveConnection(roomName)
        connection?.onDisconnect()
    }
    
    /**
     * Check if we have permission to manage calls
     */
    @RequiresApi(Build.VERSION_CODES.O)
    fun hasCallPermission(context: Context): Boolean {
        val telecomManager = context.getSystemService<TelecomManager>() ?: return false
        return telecomManager.isIncomingCallPermitted(getPhoneAccountHandle(context))
    }
    
    /**
     * Request default dialer status (required for self-managed calls on some devices)
     * Note: Not strictly required for self-managed ConnectionService
     */
    fun requestDefaultDialerRole(context: Context) {
        val telecomManager = context.getSystemService<TelecomManager>() ?: return
        
        val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).apply {
            putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, context.packageName)
        }
        
        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(intent)
        }
    }
}
