package com.mobiwha.mobiwha

import android.content.ComponentName
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.os.Bundle
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.FlutterEngineCache
import android.app.Notification
import org.json.JSONObject
import android.content.SharedPreferences
import android.content.Context

class NotificationListener : NotificationListenerService() {

    companion object {
        const val WHATSAPP_PKG = "com.whatsapp"
        const val WHATSAPP_BUSINESS_PKG = "com.whatsapp.w4b"
        const val PREFS_NAME = "mobiwha_prefs"
        const val PREFS_KEY = "pending_notifications"

        // Patterns that indicate system/non-message notifications to ignore
        val IGNORE_PATTERNS = listOf(
            "backup", "checking for new messages", "end-to-end encrypted",
            "messages and calls are end-to-end", "tap to learn more",
            "missed call", "ongoing call", "video call"
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return

        val pkg = sbn.packageName ?: return
        if (pkg != WHATSAPP_PKG && pkg != WHATSAPP_BUSINESS_PKG) return

        val extras: Bundle = sbn.notification?.extras ?: return
        val title = extras.getString(Notification.EXTRA_TITLE) ?: return
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: return

        // Skip empty or system notifications
        if (title.isBlank() || text.isBlank()) return
        val textLower = text.lowercase()
        if (IGNORE_PATTERNS.any { textLower.contains(it) }) return

        // Detect if sender is an unsaved number (starts with + or all digits/spaces/dashes)
        val isUnsaved = title.trim().matches(Regex("""^\+?[\d\s\-().]{7,20}$"""))

        // Detect group messages: text often contains "SenderName: message"
        val isGroup = extras.getString("android.substanceText") != null ||
                sbn.notification?.extras?.containsKey("android.messages") == true

        val timestamp = System.currentTimeMillis()

        // Build JSON payload
        val payload = JSONObject().apply {
            put("sender", title.trim())
            put("message", text.trim())
            put("timestamp", timestamp)
            put("isUnsaved", isUnsaved)
            put("isGroup", isGroup)
            put("source", "notification")
            put("packageName", pkg)
        }

        // Store in SharedPreferences queue (Flutter reads this)
        storeNotification(payload.toString())

        // If Flutter engine is active, send via EventChannel
        try {
            val engine = FlutterEngineCache.getInstance().get("main_engine")
            engine?.dartExecutor?.let {
                // Handled by MainActivity EventChannel sink
                MainActivity.eventSink?.success(payload.toString())
            }
        } catch (e: Exception) {
            // Engine not active – data already persisted in SharedPrefs
        }
    }

    private fun storeNotification(json: String) {
        val prefs: SharedPreferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = prefs.getString(PREFS_KEY, "[]") ?: "[]"
        // Append to simple array string
        val updated = existing.dropLast(1) + (if (existing == "[]") "" else ",") + json + "]"
        prefs.edit().putString(PREFS_KEY, updated).apply()
    }
}
