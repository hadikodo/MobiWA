package com.mobiwha.mobiwha

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity() {
    private val channelName = "com.mobiwha.mobiwha/notification_capture"
    private val chatExportRequestCode = 7294
    private val multiExportRequestCode = 7295
    private val mediaPickerRequestCode = 7296
    private var pendingChatExportResult: MethodChannel.Result? = null
    private var pendingMultiExportResult: MethodChannel.Result? = null
    private var pendingMediaPickerResult: MethodChannel.Result? = null
    private var pendingMediaPickerMimeType: String = "*/*"
    private var pendingSharedChatExport: Map<String, String>? = null

    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        cacheSharedChatExport(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        cacheSharedChatExport(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasNotificationAccess" ->
                        result.success(WhatsAppNotificationListener.hasAccess(this))

                    "openNotificationAccessSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.fromParts("package", packageName, null)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("CANNOT_OPEN_SETTINGS", e2.message, null)
                            }
                        }
                    }

                    "openAppDetailsSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", packageName, null)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CANNOT_OPEN_SETTINGS", e.message, null)
                        }
                    }

                    "hasAccessibilityAccess" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }

                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    }

                    "getInstalledWhatsAppApps" -> {
                        val apps = mutableListOf<Map<String, String>>()
                        if (isPackageInstalled("com.whatsapp.w4b")) {
                            apps.add(mapOf("packageName" to "com.whatsapp.w4b", "name" to "WhatsApp Business", "type" to "business"))
                        }
                        if (isPackageInstalled("com.whatsapp")) {
                            apps.add(mapOf("packageName" to "com.whatsapp", "name" to "WhatsApp", "type" to "normal"))
                        }
                        result.success(apps)
                    }

                    "startAutoScanWhatsApp" -> {
                        val targetPkg = call.argument<String>("packageName")
                        if (!isAccessibilityServiceEnabled()) {
                            result.error("ACCESSIBILITY_DISABLED", "Accessibility service is not enabled in Android Settings.", null)
                        } else {
                            WhatsAppAccessibilityService.startAutoCollecting(this@MainActivity, targetPkg) { numbers ->
                                runOnUiThread {
                                    result.success(numbers)
                                }
                            }
                        }
                    }

                    "scrapeChatMessages" -> {
                        val phone = call.argument<String>("phone")?.trim().orEmpty()
                        val targetPkg = call.argument<String>("packageName")
                        if (!isAccessibilityServiceEnabled()) {
                            result.error("ACCESSIBILITY_DISABLED", "Accessibility service is not enabled in Android Settings.", null)
                        } else if (!WhatsAppAccessibilityService.isServiceRunning()) {
                            result.error(
                                "SERVICE_NOT_RUNNING",
                                "MobiWA accessibility service is enabled but not running. Turn it off and on again in Accessibility Settings.",
                                null,
                            )
                        } else if (phone.isEmpty()) {
                            result.error("INVALID_PHONE", "Phone number cannot be empty.", null)
                        } else {
                            WhatsAppAccessibilityService.scrapeCurrentChatMessages(
                                phone = phone,
                                targetPackage = targetPkg,
                                context = this@MainActivity
                            ) { messages ->
                                runOnUiThread {
                                    result.success(messages)
                                }
                            }
                        }
                    }

                    "stopAutoScanWhatsApp" -> {
                        WhatsAppAccessibilityService.stopAutoCollecting(this@MainActivity)
                        result.success(true)
                    }

                    "pickWhatsAppChatExport" -> openChatExportPicker(result)

                    "takeSharedWhatsAppExport" -> {
                        result.success(pendingSharedChatExport)
                        pendingSharedChatExport = null
                    }

                    "scanWhatsAppContacts" -> {
                        try {
                            val onlyUnsaved = call.argument<Boolean>("onlyUnsaved") ?: true
                            val contacts = if (onlyUnsaved) {
                                WhatsAppContactScanner.getUnsavedWhatsAppContacts(this@MainActivity)
                            } else {
                                WhatsAppContactScanner.getAllWhatsAppContacts(this@MainActivity)
                            }
                            val mapped = contacts.map { c ->
                                mapOf(
                                    "phoneNumber" to c.phoneNumber,
                                    "displayName" to c.whatsappDisplayName,
                                )
                            }
                            result.success(mapped)
                        } catch (e: Exception) {
                            result.error(
                                "SCAN_FAILED",
                                e.message ?: "Could not scan WhatsApp contacts.",
                                null,
                            )
                        }
                    }

                    "openWhatsAppChat" -> {
                        val rawPhone = call.argument<String>("phone")?.trim().orEmpty()
                        val message = call.argument<String>("message")?.trim().orEmpty()
                        val phone = rawPhone.filter { it.isDigit() }
                        if (phone.length !in 8..15) {
                            result.error(
                                "INVALID_PHONE",
                                "Enter a phone number with its country code.",
                                null,
                            )
                        } else {
                            val uri = Uri.Builder()
                                .scheme("https")
                                .authority("wa.me")
                                .appendPath(phone)
                                .appendQueryParameter("text", message)
                                .build()
                            val intent = Intent(Intent.ACTION_VIEW, uri)
                            val isRegular = isPackageInstalled("com.whatsapp")
                            val isBusiness = isPackageInstalled("com.whatsapp.w4b")
                            if (isBusiness && !isRegular) {
                                intent.setPackage("com.whatsapp.w4b")
                            } else if (isRegular && !isBusiness) {
                                intent.setPackage("com.whatsapp")
                            }
                            try {
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.error(
                                    "WHATSAPP_UNAVAILABLE",
                                    "Could not open WhatsApp for this number.",
                                    null,
                                )
                            }
                        }
                    }

                    "pickMultipleChatExports" -> openMultiChatExportPicker(result)

                    "sendNotificationReply" -> {
                        val key = call.argument<String>("key")?.trim().orEmpty()
                        val replyText = call.argument<String>("replyText")?.trim().orEmpty()
                        if (replyText.isEmpty()) {
                            result.error("EMPTY_REPLY", "Reply text cannot be empty.", null)
                        } else {
                            val listener = WhatsAppNotificationListener.instance
                            if (listener == null) {
                                result.success(false)
                            } else {
                                val sent = listener.replyToNotification(key, replyText)
                                result.success(sent)
                            }
                        }
                    }

                    "isNotificationListenerRunning" -> {
                        result.success(WhatsAppNotificationListener.instance != null)
                    }

                    "pickMediaFile" -> {
                        val mimeType = call.argument<String>("type") ?: "*/*"
                        openMediaPicker(mimeType, result)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun openChatExportPicker(result: MethodChannel.Result) {
        if (pendingChatExportResult != null) {
            result.error("PICKER_BUSY", "A document picker is already open.", null)
            return
        }
        pendingChatExportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/plain"
        }
        try {
            startActivityForResult(intent, chatExportRequestCode)
        } catch (_: Exception) {
            pendingChatExportResult = null
            result.error("PICKER_UNAVAILABLE", "Could not open the document picker.", null)
        }
    }

    private fun openMultiChatExportPicker(result: MethodChannel.Result) {
        if (pendingMultiExportResult != null) {
            result.error("PICKER_BUSY", "A document picker is already open.", null)
            return
        }
        pendingMultiExportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/plain"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            startActivityForResult(intent, multiExportRequestCode)
        } catch (_: Exception) {
            pendingMultiExportResult = null
            result.error("PICKER_UNAVAILABLE", "Could not open the document picker.", null)
        }
    }

    private fun cacheSharedChatExport(incoming: Intent?) {
        if (incoming?.action != Intent.ACTION_SEND ||
            incoming.type?.startsWith("text/") != true
        ) return

        @Suppress("DEPRECATION")
        val extraUri = incoming.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        val uri = extraUri ?: incoming.clipData?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.uri
        if (uri != null) {
            pendingSharedChatExport = try {
                readChatExport(uri)
            } catch (_: Exception) {
                null
            }
            return
        }

        val sharedText = incoming.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (!sharedText.isNullOrBlank() &&
            sharedText.toByteArray(Charsets.UTF_8).size <= MAX_CHAT_EXPORT_BYTES
        ) {
            pendingSharedChatExport = mapOf(
                "name" to (incoming.getStringExtra(Intent.EXTRA_TITLE) ?: "WhatsApp chat export.txt"),
                "content" to sharedText,
            )
        }
    }

    @Deprecated("Deprecated by Android; FlutterActivity returns document picker results here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        // Handle single-file chat export picker
        if (requestCode == chatExportRequestCode) {
            val result = pendingChatExportResult ?: return
            pendingChatExportResult = null
            val uri = if (resultCode == RESULT_OK) data?.data else null
            if (uri == null) {
                result.success(null)
                return
            }

            try {
                result.success(readChatExport(uri))
            } catch (error: Exception) {
                result.error(
                    "CHAT_EXPORT_READ_FAILED",
                    error.message ?: "Could not read the export.",
                    null,
                )
            }
            return
        }

        // Handle multi-file chat export picker
        if (requestCode == multiExportRequestCode) {
            val result = pendingMultiExportResult ?: return
            pendingMultiExportResult = null

            if (resultCode != RESULT_OK) {
                result.success(null)
                return
            }

            try {
                val uris = mutableListOf<Uri>()

                // Single selection even in multi mode
                data?.data?.let { uris.add(it) }

                // Multiple selections
                data?.clipData?.let { clip ->
                    for (i in 0 until clip.itemCount) {
                        clip.getItemAt(i).uri?.let { uris.add(it) }
                    }
                }

                if (uris.isEmpty()) {
                    result.success(null)
                    return
                }

                val exports = uris.mapNotNull { uri ->
                    try {
                        readChatExport(uri)
                    } catch (_: Exception) {
                        null
                    }
                }

                result.success(exports)
            } catch (error: Exception) {
                result.error(
                    "MULTI_EXPORT_READ_FAILED",
                    error.message ?: "Could not read the exports.",
                    null,
                )
            }
            return
        }

        // Handle media picker for broadcasts
        if (requestCode == mediaPickerRequestCode) {
            val result = pendingMediaPickerResult ?: return
            pendingMediaPickerResult = null
            val uri = if (resultCode == RESULT_OK) data?.data else null
            if (uri == null) {
                result.success(null)
                return
            }

            try {
                val path = copyUriToCacheFile(uri, pendingMediaPickerMimeType)
                result.success(path)
            } catch (error: Exception) {
                result.error("MEDIA_PICK_FAILED", error.message ?: "Could not process media file.", null)
            }
            return
        }
    }

    private fun readChatExport(uri: Uri): Map<String, String> {
        val content = contentResolver.openInputStream(uri)?.use { stream ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var totalBytes = 0
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    totalBytes += count
                    if (totalBytes > MAX_CHAT_EXPORT_BYTES) {
                        throw IllegalArgumentException("Chat export is larger than 15 MB.")
                    }
                    output.write(buffer, 0, count)
                }
                decodeChatExport(output.toByteArray())
            } ?: throw IllegalArgumentException("Could not read the selected chat export.")

        val name = contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) cursor.getString(nameIndex) else null
        } ?: "WhatsApp chat export.txt"
        return mapOf("name" to name, "content" to content)
    }

    private fun decodeChatExport(bytes: ByteArray): String {
        if (bytes.size >= 2) {
            val first = bytes[0].toInt() and 0xff
            val second = bytes[1].toInt() and 0xff
            if (first == 0xff && second == 0xfe) {
                return String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE)
            }
            if (first == 0xfe && second == 0xff) {
                return String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE)
            }
        }
        if (bytes.size >= 3 &&
            (bytes[0].toInt() and 0xff) == 0xef &&
            (bytes[1].toInt() and 0xff) == 0xbb &&
            (bytes[2].toInt() and 0xff) == 0xbf
        ) {
            return String(bytes, 3, bytes.size - 3, StandardCharsets.UTF_8)
        }
        return String(bytes, StandardCharsets.UTF_8)
    }

    private fun isPackageInstalled(pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        if (WhatsAppAccessibilityService.isServiceRunning()) return true
        val serviceName = "$packageName/${WhatsAppAccessibilityService::class.java.name}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val colonSplitter = android.text.TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServices)
        while (colonSplitter.hasNext()) {
            val componentName = colonSplitter.next()
            if (componentName.equals(serviceName, ignoreCase = true) || componentName.contains(WhatsAppAccessibilityService::class.java.simpleName)) {
                return true
            }
        }
        return false
    }


    private fun openMediaPicker(mimeType: String, result: MethodChannel.Result) {
        if (pendingMediaPickerResult != null) {
            result.error("PICKER_BUSY", "A media picker is already open.", null)
            return
        }
        pendingMediaPickerResult = result
        pendingMediaPickerMimeType = mimeType
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
        }
        try {
            startActivityForResult(intent, mediaPickerRequestCode)
        } catch (e: Exception) {
            pendingMediaPickerResult = null
            result.error("PICKER_LAUNCH_FAILED", e.message ?: "Could not open media picker.", null)
        }
    }

    private fun copyUriToCacheFile(uri: Uri, mimeType: String): String? {
        val extension = when {
            mimeType.startsWith("image/") -> ".jpg"
            mimeType.startsWith("video/") -> ".mp4"
            mimeType.startsWith("audio/") -> ".mp3"
            else -> ""
        }
        val targetFile = java.io.File(cacheDir, "broadcast_media_${System.currentTimeMillis()}$extension")
        contentResolver.openInputStream(uri)?.use { input ->
            targetFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return targetFile.absolutePath
    }

    override fun onDestroy() {
        if (instance == this) instance = null
        methodChannel = null
        super.onDestroy()
    }

    companion object {
        private const val MAX_CHAT_EXPORT_BYTES = 15 * 1024 * 1024

        var instance: MainActivity? = null
            private set

        fun notifyNotificationReceived() {
            instance?.runOnUiThread {
                try {
                    instance?.methodChannel?.invokeMethod("onNotificationReceived", null)
                } catch (_: Exception) {}
            }
        }
    }
}

