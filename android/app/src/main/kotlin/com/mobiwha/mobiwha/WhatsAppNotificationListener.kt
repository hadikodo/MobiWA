package com.mobiwha.mobiwha

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Stores only message previews already exposed by Android notifications and handles direct AI auto-replies. */
class WhatsAppNotificationListener : NotificationListenerService() {
    private val writer = Executors.newSingleThreadExecutor()

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        activeNotifications.orEmpty().forEach(::captureNotification)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        captureNotification(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        super.onNotificationRemoved(sbn)
    }

    private fun captureNotification(sbn: StatusBarNotification) {
        if (sbn.packageName !in whatsappPackages) return
        val notification = sbn.notification ?: return
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        if (notification.category == Notification.CATEGORY_CALL) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        if (title.isBlank() || title.length > 300) return
        if (title.equals("WhatsApp", ignoreCase = true) ||
            title.equals("WhatsApp Business", ignoreCase = true)) return

        val messagingStyle = NotificationCompat.MessagingStyle
            .extractMessagingStyleFromNotification(notification)
        val isGroup = messagingStyle?.isGroupConversation
            ?: extras.getBoolean("android.isGroupConversation", false)
        if (messagingStyle != null) {
            val ownPerson = messagingStyle.user
            val messages = messagingStyle.historicMessages + messagingStyle.messages
            for (entry in messages) {
                val message = entry.text.toString().trim()
                val person = entry.person
                val senderName = person?.name?.toString()?.trim()
                    ?: entry.sender?.toString()?.trim().orEmpty()
                if (message.isBlank() || message.length > 4000) continue
                val ownKey = ownPerson.key.orEmpty()
                val senderKey = person?.key.orEmpty()
                val sameSender = when {
                    senderKey.isNotBlank() && ownKey.isNotBlank() ->
                        senderKey == ownKey
                    person != null -> person.name?.toString()
                        ?.equals(ownPerson.name?.toString(), ignoreCase = true) == true
                    else -> senderName.equals(
                        ownPerson.name?.toString(),
                        ignoreCase = true,
                    ) || senderName.equals("You", ignoreCase = true) ||
                        senderName.equals("Me", ignoreCase = true)
                }
                if (sameSender) continue

                val groupEntry = isGroup || (senderName.isNotBlank() &&
                    !senderName.equals(title, ignoreCase = true))
                val rawSender = if (groupEntry) senderName else title
                if (rawSender.isBlank() || rawSender.length > 300) continue

                val personKey = person?.key.orEmpty()
                val personUri = person?.uri.orEmpty()
                val jidDigits = if (personKey.contains("@")) {
                    personKey.substringBefore("@").filter { it.isDigit() }
                } else {
                    personKey.filter { it.isDigit() }
                }
                val uriDigits = if (personUri.startsWith("tel:")) {
                    personUri.removePrefix("tel:").filter { it.isDigit() }
                } else {
                    personUri.filter { it.isDigit() }
                }
                val phoneDigits = if (uriDigits.length in 7..16) uriDigits else if (jidDigits.length in 7..16) jidDigits else ""
                val sender = if (phoneDigits.isNotEmpty() && rawSender.filter { it.isDigit() }.length < 6) {
                    "$rawSender (+$phoneDigits)"
                } else {
                    rawSender
                }

                enqueuePreview(sbn, title, sender, message, entry.timestamp)
            }
            return
        }

        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim().orEmpty()
        if (body.isBlank() || body.length > 4000) return
        val separator = body.indexOf(": ")
        val sender: String
        val message: String
        if (isGroup) {
            // Group previews usually contain "sender: message". Without a sender,
            // do not create a lead under the group title.
            if (separator <= 0 || separator > 150 || body.contains('\n')) return
            sender = body.substring(0, separator).trim()
            message = body.substring(separator + 2).trim()
        } else {
            sender = title
            message = body
        }
        if (sender.isBlank() || message.isBlank()) return

        enqueuePreview(sbn, title, sender, message, sbn.postTime)
    }

    private fun enqueuePreview(
        sbn: StatusBarNotification,
        conversation: String,
        sender: String,
        message: String,
        timestamp: Long,
    ) {
        val time = if (timestamp > 0) timestamp else sbn.postTime
        val packageName = sbn.packageName
        val keySource = "$packageName|$conversation|$sender|$time|$message"
        val messageHash = MessageDigest.getInstance("SHA-256")
            .digest(keySource.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        val uniqueKey = "$packageName|$conversation|$sender|$time|$messageHash"

        // Cache StatusBarNotification for direct auto-replies
        synchronized(activeNotificationMap) {
            activeNotificationMap[uniqueKey] = sbn
            if (sender.isNotBlank()) {
                activeNotificationMap[sender.lowercase().trim()] = sbn
            }
            if (conversation.isNotBlank()) {
                activeNotificationMap[conversation.lowercase().trim()] = sbn
            }
        }

        writer.execute {
            savePreview(uniqueKey, packageName, sender, message, time)
            MainActivity.notifyNotificationReceived()
        }
    }

    private fun savePreview(key: String, packageName: String, sender: String, message: String, timestamp: Long) {
        val dbFile = getDatabasePath("mobiwa_local.db")
        repeat(3) { attempt ->
            var db: SQLiteDatabase? = null
            try {
                db = SQLiteDatabase.openDatabase(
                    dbFile.path,
                    null,
                    SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY,
                )
                db.execSQL("PRAGMA busy_timeout=3000")
                if (!db.isReadOnly) {
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS pending_notifications (" +
                            "notification_key TEXT PRIMARY KEY, " +
                            "package_name TEXT NOT NULL, " +
                            "sender TEXT NOT NULL, " +
                            "message TEXT NOT NULL, " +
                            "timestamp INTEGER NOT NULL)",
                    )
                    db.execSQL(
                        "INSERT OR IGNORE INTO pending_notifications " +
                            "(notification_key, package_name, sender, message, timestamp) VALUES (?, ?, ?, ?, ?)",
                        arrayOf<Any?>(key, packageName, sender, message, timestamp)
                    )
                }
                return
            } catch (_: Exception) {
                if (attempt < 2) Thread.sleep(200)
            } finally {
                db?.close()
            }
        }
    }

    /**
     * Sends a direct reply to the active notification via Android RemoteInput.
     * Works seamlessly with WhatsApp and WhatsApp Business without opening the app UI.
     */
    fun replyToNotification(keyOrSender: String, replyText: String): Boolean {
        val sbn = synchronized(activeNotificationMap) {
            activeNotificationMap[keyOrSender] ?: activeNotificationMap[keyOrSender.lowercase().trim()]
        } ?: return false
        val notification = sbn.notification ?: return false

        // 1. Try AndroidX NotificationCompat direct reply
        val count = NotificationCompat.getActionCount(notification)
        for (i in 0 until count) {
            val action = NotificationCompat.getAction(notification, i) ?: continue
            val remoteInputs = action.remoteInputs ?: continue
            val pendingIntent = action.actionIntent ?: continue
            for (remoteInput in remoteInputs) {
                val intent = Intent()
                val bundle = Bundle()
                bundle.putCharSequence(remoteInput.resultKey, replyText)
                RemoteInput.addResultsToIntent(arrayOf(remoteInput), intent, bundle)
                try {
                    pendingIntent.send(this, 0, intent)
                    Log.d("WhatsAppNotification", "Direct reply sent successfully via NotificationCompat")
                    return true
                } catch (e: Exception) {
                    Log.e("WhatsAppNotification", "Direct reply via NotificationCompat failed: ${e.message}", e)
                }
            }
        }

        // 2. Try platform Notification.Action direct reply
        notification.actions?.forEach { action ->
            val pendingIntent = action.actionIntent ?: return@forEach
            action.remoteInputs?.forEach { remoteInput ->
                val intent = Intent()
                val bundle = Bundle()
                bundle.putCharSequence(remoteInput.resultKey, replyText)
                android.app.RemoteInput.addResultsToIntent(arrayOf(remoteInput), intent, bundle)
                try {
                    pendingIntent.send(this, 0, intent)
                    Log.d("WhatsAppNotification", "Direct reply sent successfully via native Action")
                    return true
                } catch (e: Exception) {
                    Log.e("WhatsAppNotification", "Direct reply via native Action failed: ${e.message}", e)
                }
            }
        }

        return false
    }

    override fun onDestroy() {
        instance = null
        writer.shutdown()
        super.onDestroy()
    }

    companion object {
        private val whatsappPackages = setOf("com.whatsapp", "com.whatsapp.w4b")

        var instance: WhatsAppNotificationListener? = null
            private set

        private val activeNotificationMap = object : LinkedHashMap<String, StatusBarNotification>(100, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, StatusBarNotification>?): Boolean {
                return size > 100
            }
        }

        fun hasAccess(context: Context): Boolean {
            try {
                if (androidx.core.app.NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)) {
                    return true
                }
            } catch (_: Exception) {}

            val enabled = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            val component1 = ComponentName(context, WhatsAppNotificationListener::class.java).flattenToString()
            val component2 = ComponentName(context, WhatsAppNotificationListener::class.java).flattenToShortString()
            val pkg = context.packageName
            return enabled.split(":").any {
                it.equals(component1, ignoreCase = true) ||
                it.equals(component2, ignoreCase = true) ||
                it.startsWith("$pkg/", ignoreCase = true)
            }
        }
    }
}
