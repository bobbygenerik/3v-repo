package com.example.tres3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class CallForegroundService : Service() {
    
    companion object {
        private const val TAG = "CallForegroundService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "call_service_channel"
        private const val CHANNEL_NAME = "Active Call"
        
        const val ACTION_START = "com.example.tres3.action.START_CALL_SERVICE"
        const val ACTION_STOP = "com.example.tres3.action.STOP_CALL_SERVICE"
        const val EXTRA_RECIPIENT_NAME = "recipient_name"
        
        fun start(context: Context, recipientName: String) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RECIPIENT_NAME, recipientName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stop(context: Context) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: action=${intent?.action}")
        
        when (intent?.action) {
            ACTION_START -> {
                val recipientName = intent.getStringExtra(EXTRA_RECIPIENT_NAME) ?: "Unknown"
                startForeground(NOTIFICATION_ID, createNotification(recipientName))
                Log.d(TAG, "Started foreground service for call with $recipientName")
            }
            ACTION_STOP -> {
                Log.d(TAG, "Stopping foreground service")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        
        return START_NOT_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows ongoing call notification"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }
    
    private fun createNotification(recipientName: String): Notification {
        val contentIntent = Intent(this, InCallActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Active Call")
            .setContentText("In call with $recipientName")
            .setSmallIcon(R.drawable.ic_phone) // You'll need to add this icon
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
    }
}
