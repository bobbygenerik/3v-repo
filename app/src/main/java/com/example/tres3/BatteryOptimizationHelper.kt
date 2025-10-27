package com.example.tres3

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.appcompat.app.AlertDialog

object BatteryOptimizationHelper {
    
    private const val TAG = "BatteryOptimization"
    
    /**
     * Check if the app is exempt from battery optimizations
     */
    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        // minSdk is 24, so we can safely assume M (23) is available
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val isIgnoring = powerManager.isIgnoringBatteryOptimizations(context.packageName)
        Log.d(TAG, "Is ignoring battery optimizations: $isIgnoring")
        return isIgnoring
    }
    
    /**
     * Request battery optimization exemption with explanation dialog
     */
    fun requestBatteryOptimizationExemption(context: Context, onResult: ((Boolean) -> Unit)? = null) {
        if (isIgnoringBatteryOptimizations(context)) {
            Log.d(TAG, "Already exempt from battery optimizations")
            onResult?.invoke(true)
            return
        }
        
        // Show explanation dialog first
        AlertDialog.Builder(context)
            .setTitle("Battery Optimization")
            .setMessage(
                "To ensure reliable video calls, this app needs to run without battery restrictions. " +
                "This prevents the system from freezing the app during or after calls.\n\n" +
                "Please select \"Allow\" on the next screen."
            )
            .setPositiveButton("Continue") { dialog, _ ->
                dialog.dismiss()
                openBatteryOptimizationSettings(context)
                onResult?.invoke(false) // User needs to manually enable it
            }
            .setNegativeButton("Not Now") { dialog, _ ->
                dialog.dismiss()
                Log.d(TAG, "User declined battery optimization exemption")
                onResult?.invoke(false)
            }
            .setCancelable(false)
            .show()
    }
    
    /**
     * Open battery optimization settings for this app
     */
    private fun openBatteryOptimizationSettings(context: Context) {
        // minSdk is 24, so M (23) is always available
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
            context.startActivity(intent)
            Log.d(TAG, "Opened battery optimization settings")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open battery optimization settings", e)
            // Fallback to general battery settings
            try {
                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                context.startActivity(intent)
            } catch (e2: Exception) {
                Log.e(TAG, "Failed to open general battery settings", e2)
            }
        }
    }
    
    /**
     * Check if we should request battery optimization exemption
     * (Only ask once per app install or after updates)
     */
    fun shouldRequestBatteryOptimization(context: Context): Boolean {
        if (isIgnoringBatteryOptimizations(context)) {
            return false
        }
        
        val prefs = context.getSharedPreferences("battery_opt_prefs", Context.MODE_PRIVATE)
        val hasAsked = prefs.getBoolean("has_asked_battery_opt", false)
        
        if (!hasAsked) {
            // Mark as asked
            prefs.edit().putBoolean("has_asked_battery_opt", true).apply()
            return true
        }
        
        return false
    }
    
    /**
     * Show a non-intrusive reminder about battery optimization
     */
    fun showReminderIfNeeded(context: Context) {
        if (!isIgnoringBatteryOptimizations(context)) {
            Log.w(TAG, "⚠️ App is subject to battery optimization - calls may be interrupted")
        }
    }
}
