package com.mobiwha.mobiwha

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
        private const val METHOD_CHANNEL = "com.mobiwha/control"
        private const val EVENT_CHANNEL = "com.mobiwha/notifications"
        private const val PREFS_NAME = "mobiwha_prefs"
        private const val PREFS_KEY = "pending_notifications"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cache engine for use by NotificationListener
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

        // EventChannel: push real-time notifications to Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Flush any pending notifications that came in while app was closed
                    flushPendingNotifications(events)
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // MethodChannel: Flutter calls native functions
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasNotificationPermission" -> {
                        result.success(isNotificationListenerEnabled())
                    }
                    "openNotificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    }
                    "requestBatteryOptimizationExemption" -> {
                        requestBatteryExemption()
                        result.success(true)
                    }
                    "isBatteryOptimizationIgnored" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "getWhatsAppBackupPaths" -> {
                        result.success(getWhatsAppBackupPaths())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return enabledListeners.contains(packageName)
    }

    private fun requestBatteryExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        }
    }

    private fun getWhatsAppBackupPaths(): List<String> {
        return listOf(
            "/sdcard/WhatsApp/Databases/msgstore.db",
            "/storage/emulated/0/WhatsApp/Databases/msgstore.db",
            "/sdcard/Android/media/com.whatsapp/WhatsApp/Databases/msgstore.db",
            "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Databases/msgstore.db",
            // WhatsApp Business paths
            "/sdcard/WhatsApp Business/Databases/msgstore.db",
            "/storage/emulated/0/WhatsApp Business/Databases/msgstore.db",
        )
    }

    private fun flushPendingNotifications(sink: EventChannel.EventSink?) {
        sink ?: return
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pending = prefs.getString(PREFS_KEY, "[]") ?: "[]"
        if (pending != "[]") {
            sink.success(pending) // Send bulk as JSON array string
            prefs.edit().putString(PREFS_KEY, "[]").apply()
        }
    }
}
