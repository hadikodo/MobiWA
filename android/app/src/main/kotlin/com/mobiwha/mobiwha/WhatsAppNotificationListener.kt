package com.mobiwha.mobiwha

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.provider.Settings
import androidx.core.app.NotificationCompat
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Stores only message previews already exposed by Android notifications. */
class WhatsAppNotificationListener : NotificationListenerService() {
    private val writer = Executors.newSingleThreadExecutor()

    override fun onListenerConnected() {
        super.onListenerConnected()
        activeNotifications.orEmpty().forEach(::captureNotification)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        captureNotification(sbn)
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
                val sender = if (groupEntry) senderName else title
                if (sender.isBlank() || sender.length > 300) continue
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
        writer.execute { savePreview(uniqueKey, packageName, sender, message, time) }
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
                    // The listener can receive notifications before Flutter has
                    // initialized the app database. Create only its queue table;
                    // sqflite's normal onCreate will add the remaining schema.
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
                // The app may be upgrading or its database may be temporarily locked.
                if (attempt < 2) Thread.sleep(200)
            } finally {
                db?.close()
            }
        }
    }

    override fun onDestroy() {
        writer.shutdown()
        super.onDestroy()
    }

    companion object {
        private val whatsappPackages = setOf("com.whatsapp", "com.whatsapp.w4b")

        fun hasAccess(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            val component = ComponentName(context, WhatsAppNotificationListener::class.java).flattenToString()
            return enabled.split(":").any { it.equals(component, ignoreCase = true) }
        }
    }
}
