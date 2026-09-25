package com.mobiwha.mobiwha

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.provider.Settings

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            // Re-enable notification listener if it was previously granted
            val enabledListeners = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            )
            val componentName = ComponentName(context, NotificationListener::class.java)
            if (enabledListeners != null && enabledListeners.contains(componentName.flattenToString())) {
                // Listener is still enabled – Android will auto-rebind it on boot
                // Nothing more needed; service starts automatically
            }
        }
    }
}
