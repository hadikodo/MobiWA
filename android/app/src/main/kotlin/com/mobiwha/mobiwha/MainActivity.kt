package com.mobiwha.mobiwha

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.text.TextUtils
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridge between Flutter and Android. Channel: "com.mobiwha/automation".
 *
 * Dart → Android: see the `when` block below.
 * Android → Dart: onScanProgress(count), onStopRequested().
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.mobiwha/automation"
        private const val PICK_MEDIA = 8101
        private const val CONTACTS_PERMISSION = 8102
        private const val MAX_MEDIA_BYTES = 100L * 1024 * 1024 // WhatsApp's own limit

        private var channel: MethodChannel? = null

        fun emit(method: String, args: Any?) {
            val ch = channel ?: return
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try { ch.invokeMethod(method, args) } catch (_: Exception) {}
            }
        }
    }

    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            val service = WhatsAppAccessibilityService.instance
            when (call.method) {
                "getInstalledApps" -> result.success(
                    listOf(WhatsAppAccessibilityService.WA, WhatsAppAccessibilityService.WA_BUSINESS)
                        .filter { isInstalled(it) },
                )

                "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())

                // "running" | "stopped" (enabled in Settings but killed by the phone) | "off"
                "getAccessibilityState" -> result.success(accessibilityState())

                "tryRestartAccessibility" -> tryRestartAccessibility(result)

                "getDeviceInfo" -> result.success(
                    mapOf(
                        "id" to (Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""),
                        "name" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}".trim(),
                    ),
                )

                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }

                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        @Suppress("BatteryLife")
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(Uri.parse("package:$packageName")),
                        )
                        result.success(true)
                    } catch (_: Exception) {
                        openAppDetails()
                        result.success(false)
                    }
                }

                "openAutostartSettings" -> result.success(openAutostartSettings())

                "isXiaomi" -> result.success(
                    android.os.Build.MANUFACTURER.lowercase().let {
                        it.contains("xiaomi") || it.contains("redmi") || it.contains("poco")
                    },
                )

                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }

                "scanUnsaved" -> {
                    val pkg = call.argument<String>("package") ?: WhatsAppAccessibilityService.WA
                    if (service == null) return@setMethodCallHandler notRunning(result)
                    service.startScan(pkg) { numbers -> runOnUiThread { result.success(numbers) } }
                }

                "readChat" -> {
                    val phone = call.argument<String>("phone").orEmpty()
                    val pkg = call.argument<String>("package") ?: WhatsAppAccessibilityService.WA
                    if (service == null) return@setMethodCallHandler notRunning(result)
                    service.startRead(phone, pkg) { data -> runOnUiThread { result.success(data) } }
                }

                "sendMessage" -> {
                    if (service == null) return@setMethodCallHandler notRunning(result)
                    service.startSend(
                        phone = call.argument<String>("phone").orEmpty(),
                        pkg = call.argument<String>("package") ?: WhatsAppAccessibilityService.WA,
                        text = call.argument<String>("text").orEmpty(),
                        mediaPath = call.argument<String>("mediaPath"),
                        mimeType = call.argument<String>("mimeType"),
                    ) { status -> runOnUiThread { result.success(status) } }
                }

                "cancelJob" -> {
                    service?.cancelCurrentJob()
                    result.success(null)
                }

                "showOverlay" -> {
                    service?.showOverlay(call.argument<String>("text").orEmpty())
                    result.success(null)
                }

                "updateOverlay" -> {
                    service?.updateOverlay(call.argument<String>("text").orEmpty())
                    result.success(null)
                }

                "hideOverlay" -> {
                    service?.hideOverlay()
                    result.success(null)
                }

                "returnToApp" -> {
                    if (service != null) service.returnToApp() else bringToFront()
                    result.success(null)
                }

                "openChat" -> {
                    val digits = call.argument<String>("phone").orEmpty().filter { it.isDigit() }
                    val pkg = call.argument<String>("package")
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$digits")).apply {
                        if (pkg != null && isInstalled(pkg)) setPackage(pkg)
                    }
                    try {
                        startActivity(intent); result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                "pickMedia" -> pickMedia(call.argument<String>("mime") ?: "*/*", result)

                "hasContactsPermission" -> result.success(hasContactsPermission())

                // → "granted" | "denied" | "blocked" (denied with "don't ask again")
                "requestContactsPermission" -> requestContactsPermission(result)

                "openAppSettings" -> {
                    openAppDetails()
                    result.success(null)
                }

                "getPhoneContacts" -> {
                    if (!hasContactsPermission()) {
                        result.error("NO_PERMISSION", "Allow MobiWA to read your contacts first.", null)
                    } else {
                        // Big address books: read off the main thread.
                        Thread {
                            try {
                                val list = PhoneContacts.read(applicationContext)
                                runOnUiThread { result.success(list) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("CONTACTS_FAILED", e.message ?: "Could not read contacts.", null)
                                }
                            }
                        }.start()
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private var pendingContactsPermission: MethodChannel.Result? = null

    private fun hasContactsPermission(): Boolean =
        checkSelfPermission(android.Manifest.permission.READ_CONTACTS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    private fun requestContactsPermission(result: MethodChannel.Result) {
        if (hasContactsPermission()) { result.success("granted"); return }
        if (pendingContactsPermission != null) { result.success("denied"); return }
        pendingContactsPermission = result
        requestPermissions(arrayOf(android.Manifest.permission.READ_CONTACTS), CONTACTS_PERMISSION)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CONTACTS_PERMISSION) return
        val result = pendingContactsPermission ?: return
        pendingContactsPermission = null
        when {
            hasContactsPermission() -> result.success("granted")
            // No rationale after a denial = "Don't ask again"; only Settings can fix it.
            !shouldShowRequestPermissionRationale(android.Manifest.permission.READ_CONTACTS) ->
                result.success("blocked")
            else -> result.success("denied")
        }
    }

    private fun notRunning(result: MethodChannel.Result) {
        result.error(
            "ACCESSIBILITY_OFF",
            "Turn on \"MobiWA Automation\" in Accessibility settings first.",
            null,
        )
    }

    private fun bringToFront() {
        packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }?.let { startActivity(it) }
    }

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0); true
    } catch (_: Exception) {
        false
    }

    private fun serviceComponent(): String =
        "$packageName/${WhatsAppAccessibilityService::class.java.name}"

    private fun accessibilityState(): String = when {
        WhatsAppAccessibilityService.isRunning() -> "running"
        isAccessibilityEnabled() -> "stopped"
        else -> "off"
    }

    /**
     * Android stops binding a service that "crashed" (its process was killed)
     * until it is switched off and on again, and MIUI even removes it from the
     * enabled list on force-stop / reinstall. With WRITE_SECURE_SETTINGS
     * (granted once over adb) we re-enable it ourselves — only if the user had
     * switched it on before.
     */
    private fun tryRestartAccessibility(result: MethodChannel.Result) {
        if (WhatsAppAccessibilityService.isRunning()) { result.success(true); return }
        val granted = checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted) { result.success(false); return }
        // Only bring back what the user had switched on before.
        val wanted = getSharedPreferences("mobiwa_native", MODE_PRIVATE)
            .getBoolean("automation_wanted", false)
        if (!wanted) { result.success(false); return }
        try {
            val key = Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            val me = serviceComponent()
            val others = (Settings.Secure.getString(contentResolver, key) ?: "")
                .split(':').filter { it.isNotBlank() && !it.equals(me, ignoreCase = true) }
            Settings.Secure.putString(contentResolver, key, others.joinToString(":"))
            android.os.Handler(mainLooper).postDelayed({
                try {
                    Settings.Secure.putString(contentResolver, key, (others + me).joinToString(":"))
                    Settings.Secure.putInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
                } catch (_: Exception) {}
                // Give the system a moment to bind the service again.
                android.os.Handler(mainLooper).postDelayed({
                    result.success(WhatsAppAccessibilityService.isRunning())
                }, 1500)
            }, 400)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun openAppDetails() {
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", packageName, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {}
    }

    /** Xiaomi / Redmi / POCO autostart screen, falling back to App info. */
    private fun openAutostartSettings(): Boolean {
        val candidates = listOf(
            Intent().setClassName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT),
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")
                .putExtra("extra_pkgname", packageName),
        )
        for (intent in candidates) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {}
        }
        openAppDetails()
        return false
    }

    private fun isAccessibilityEnabled(): Boolean {
        if (WhatsAppAccessibilityService.isRunning()) return true
        val expected = "$packageName/${WhatsAppAccessibilityService::class.java.name}"
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':').apply { setString(enabled) }
        for (entry in splitter) if (entry.equals(expected, ignoreCase = true)) return true
        return false
    }

    // ---------------------------------------------------------------------
    // Media picker: copies the chosen file into app storage so it can be
    // shared to WhatsApp for every recipient of a campaign.
    // ---------------------------------------------------------------------

    private fun pickMedia(mime: String, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("PICKER_BUSY", "A file picker is already open.", null); return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, PICK_MEDIA)
        } catch (e: Exception) {
            pendingPick = null
            result.error("PICKER_UNAVAILABLE", "Could not open the file picker.", null)
        }
    }

    @Deprecated("FlutterActivity still delivers picker results here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_MEDIA) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) { result.success(null); return }
        try {
            result.success(copyToMediaDir(uri))
        } catch (e: Exception) {
            result.error("MEDIA_COPY_FAILED", e.message ?: "Could not read the file.", null)
        }
    }

    private fun copyToMediaDir(uri: Uri): Map<String, Any> {
        val mime = contentResolver.getType(uri) ?: "application/octet-stream"
        var name = "file"
        var size = -1L
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) ?: name }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }?.let { size = c.getLong(it) }
            }
        }
        if (size > MAX_MEDIA_BYTES) throw IllegalArgumentException("File is larger than 100 MB.")

        val dir = File(filesDir, "send_media").apply { mkdirs() }
        // Keep the folder small: drop files older than 30 days.
        val cutoff = System.currentTimeMillis() - 30L * 24 * 60 * 60 * 1000
        dir.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }

        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
            ?: name.substringAfterLast('.', "bin")
        val safeBase = name.substringBeforeLast('.').replace(Regex("[^A-Za-z0-9_\\-]"), "_").take(40)
        val target = File(dir, "${System.currentTimeMillis()}_$safeBase.$ext")
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { input.copyTo(it) }
        } ?: throw IllegalArgumentException("Could not read the file.")

        return mapOf(
            "path" to target.absolutePath,
            "name" to name,
            "mime" to mime,
            "size" to target.length(),
        )
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }
}
