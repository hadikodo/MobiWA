package com.mobiwha.mobiwha

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.FileProvider
import java.io.File

/**
 * All WhatsApp automation lives here. Nothing happens unless the app explicitly
 * starts one of three jobs:
 *
 *  - [startScan]  scroll the WhatsApp chat list and collect chat titles that are
 *                 phone numbers (= numbers not saved in contacts).
 *  - [startRead]  open one chat and read its visible messages (for the AI).
 *  - [startSend]  open one chat (text) or the share sheet (media), press Send.
 *
 * Only one job runs at a time. Each job always calls its callback exactly once.
 */
class WhatsAppAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "MobiWA.A11y"
        const val WA = "com.whatsapp"
        const val WA_BUSINESS = "com.whatsapp.w4b"

        var instance: WhatsAppAccessibilityService? = null
            private set

        fun isRunning(): Boolean = instance != null

        private val SEND_WORDS = setOf(
            "send", "إرسال", "ارسال", "أرسل", "enviar", "envoyer", "senden", "invia",
            "отправить", "gönder", "kirim", "enviar mensagem",
        )
    }

    private enum class Job { NONE, SCAN, READ, SEND }

    private val handler = Handler(Looper.getMainLooper())
    private var job = Job.NONE
    /** Incremented for every job so stale delayed steps can detect they are obsolete. */
    private var jobToken = 0
    private var targetPkg = WA

    // ---------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        // Remember that the user switched the automation on, so MainActivity may
        // switch it back on after Android/MIUI turned it off (force-stop, update).
        getSharedPreferences("mobiwa_native", MODE_PRIVATE).edit()
            .putBoolean("automation_wanted", true).apply()
        Log.d(TAG, "Service connected")
    }

    override fun onDestroy() {
        cancelCurrentJob()
        hideOverlay()
        instance = null
        super.onDestroy()
    }

    // Jobs are driven by timed polling steps, not by events. Ignoring events here is
    // deliberate: the service must never act on WhatsApp on its own.
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    fun isBusy(): Boolean = job != Job.NONE

    private fun later(delayMs: Long, step: () -> Unit) {
        val token = jobToken
        handler.postDelayed({ if (token == jobToken && job != Job.NONE) step() }, delayMs)
    }

    private fun beginJob(newJob: Job, pkg: String) {
        jobToken++
        job = newJob
        targetPkg = pkg
    }

    private fun endJob() {
        jobToken++
        job = Job.NONE
    }

    /** Stops whatever is running; the running job reports its partial result. */
    fun cancelCurrentJob() {
        when (job) {
            Job.SCAN -> finishScan()
            Job.READ -> finishRead()
            Job.SEND -> finishSend("cancelled")
            Job.NONE -> {}
        }
    }

    // ---------------------------------------------------------------------
    // Shared helpers
    // ---------------------------------------------------------------------

    /** Root node of the target WhatsApp window, or null when WhatsApp is not in front. */
    private fun waRoot(): AccessibilityNodeInfo? {
        val active = rootInActiveWindow
        if (active?.packageName?.toString() == targetPkg) return active
        try {
            for (w in windows) {
                val r = w.root ?: continue
                if (r.packageName?.toString() == targetPkg) return r
            }
        } catch (_: Exception) {}
        return null
    }

    private fun byId(root: AccessibilityNodeInfo, id: String): List<AccessibilityNodeInfo> =
        try {
            root.findAccessibilityNodeInfosByViewId("$targetPkg:id/$id")
        } catch (_: Exception) {
            emptyList()
        }

    private fun click(node: AccessibilityNodeInfo): Boolean {
        var n: AccessibilityNodeInfo? = node
        var depth = 0
        while (n != null && !n.isClickable && depth < 6) {
            n = n.parent
            depth++
        }
        return (n ?: node).performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun isConversationScreen(root: AccessibilityNodeInfo): Boolean =
        byId(root, "entry").isNotEmpty() || byId(root, "conversation_contact_name").isNotEmpty()

    /** WhatsApp shows a dialog instead of a chat when the number is not registered. */
    private fun findNotOnWhatsAppDialog(node: AccessibilityNodeInfo?, depth: Int = 0): Boolean {
        if (node == null || depth > 25) return false
        val text = node.text?.toString()?.lowercase().orEmpty()
        if (text.isNotEmpty() && (
                (text.contains("whatsapp") && (text.contains("isn't") || text.contains("is not") || text.contains("not on"))) ||
                text.contains("url is invalid") ||
                text.contains("غير موجود على واتساب") ||
                text.contains("ليس على واتساب") ||
                text.contains("غير مسجل")
            )
        ) return true
        for (i in 0 until node.childCount) {
            if (findNotOnWhatsAppDialog(node.getChild(i), depth + 1)) return true
        }
        return false
    }

    private fun dismissDialog(root: AccessibilityNodeInfo) {
        val ok = root.findAccessibilityNodeInfosByViewId("android:id/button1").firstOrNull()
        if (ok != null) click(ok) else performGlobalAction(GLOBAL_ACTION_BACK)
    }

    private fun findVerticalList(node: AccessibilityNodeInfo?, depth: Int = 0): AccessibilityNodeInfo? {
        if (node == null || depth > 30) return null
        val cls = node.className?.toString().orEmpty()
        val horizontal = cls.contains("ViewPager", true) || cls.contains("HorizontalScrollView", true) ||
            cls.contains("TabLayout", true)
        if (!horizontal && node.isScrollable &&
            (cls.contains("RecyclerView") || cls.contains("ListView") || cls.contains("ScrollView"))
        ) return node
        for (i in 0 until node.childCount) {
            findVerticalList(node.getChild(i), depth + 1)?.let { return it }
        }
        return null
    }

    private fun swipe(fromYRatio: Float, toYRatio: Float) {
        val m = resources.displayMetrics
        val x = m.widthPixels / 2f
        val path = Path().apply {
            moveTo(x, m.heightPixels * fromYRatio)
            lineTo(x, m.heightPixels * toYRatio)
        }
        dispatchGesture(
            GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, 250))
                .build(),
            null, null,
        )
    }

    private fun launchWhatsAppHome(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        return try {
            startActivity(intent); true
        } catch (e: Exception) {
            Log.e(TAG, "Cannot launch $pkg: ${e.message}"); false
        }
    }

    fun returnToApp() {
        try {
            packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
                )
            }?.let { startActivity(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Cannot return to MobiWA: ${e.message}")
        }
    }

    // ---------------------------------------------------------------------
    // 1. SCAN — collect unsaved numbers from the chat list
    // ---------------------------------------------------------------------

    private val scanned = LinkedHashSet<String>()
    private val seenScreens = HashSet<String>()
    private var scanCallback: ((List<String>) -> Unit)? = null
    private var scanAttempts = 0
    private var scanStagnant = 0
    private var scanTopReached = false
    private var scanTopScrolls = 0
    private var scanStartedAt = 0L

    fun startScan(pkg: String, onDone: (List<String>) -> Unit) {
        if (isBusy()) { onDone(emptyList()); return }
        beginJob(Job.SCAN, pkg)
        scanCallback = onDone
        scanned.clear(); seenScreens.clear()
        scanAttempts = 0; scanStagnant = 0; scanTopReached = false; scanTopScrolls = 0
        scanStartedAt = System.currentTimeMillis()
        if (!launchWhatsAppHome(pkg)) { finishScan(); return }
        later(2200) { scanStep() }
    }

    private fun scanStep() {
        val root = waRoot()
        if (root == null) {
            if (++scanAttempts > 15) { finishScan(); return }
            later(700) { scanStep() }
            return
        }
        // WhatsApp sometimes restores the last open chat: go back to the chat list.
        if (isConversationScreen(root)) {
            performGlobalAction(GLOBAL_ACTION_BACK)
            later(900) { scanStep() }
            return
        }

        val list = findVerticalList(root)

        // Phase 1: make sure we start from the very top of the chat list.
        if (!scanTopReached) {
            val moved = list?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) ?: false
            if (moved && ++scanTopScrolls < 60) { later(250) { scanStep() }; return }
            scanTopReached = true
            later(500) { scanStep() }
            return
        }

        // Phase 2: collect, then scroll down until the list stops moving.
        val before = scanned.size
        val signature = collectNumbers(root)
        val newScreen = signature.isNotEmpty() && seenScreens.add(signature)
        if (scanned.size > before) {
            MainActivity.emit("onScanProgress", scanned.size)
            updateOverlay("Getting numbers… ${scanned.size} found")
        }

        val scrolled = list?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) ?: false
        if (!scrolled) swipe(0.75f, 0.30f)

        scanStagnant = if (!newScreen) scanStagnant + 1 else 0
        val tooLong = System.currentTimeMillis() - scanStartedAt > 15 * 60 * 1000
        if (scanStagnant >= 4 || tooLong) { finishScan(); return }
        later(650) { scanStep() }
    }

    /** Adds phone-number chat titles from the visible screen. Returns a screen signature. */
    private fun collectNumbers(root: AccessibilityNodeInfo): String {
        val titleNodes = byId(root, "conversations_row_contact_name")
        val sig = StringBuilder()
        if (titleNodes.isNotEmpty()) {
            for (n in titleNodes) {
                val t = n.text?.toString() ?: continue
                sig.append(t).append('|')
                phoneFromTitle(t, requirePlus = false)?.let { scanned.add(it) }
            }
        } else {
            // Unknown WhatsApp layout: read every text, but only accept "+…" numbers.
            walkTexts(root) { t ->
                sig.append(t).append('|')
                phoneFromTitle(t, requirePlus = true)?.let { scanned.add(it) }
            }
        }
        return sig.toString()
    }

    private fun walkTexts(node: AccessibilityNodeInfo?, depth: Int = 0, onText: (String) -> Unit) {
        if (node == null || depth > 40) return
        node.text?.toString()?.takeIf { it.isNotBlank() }?.let(onText)
        for (i in 0 until node.childCount) walkTexts(node.getChild(i), depth + 1, onText)
    }

    /** "+961 70 123 456" → "+96170123456"; anything that is not purely a phone number → null. */
    private fun phoneFromTitle(raw: String, requirePlus: Boolean): String? {
        val normalized = buildString {
            for (c in raw) {
                when (c) {
                    in '٠'..'٩' -> append('0' + (c - '٠'))
                    in '۰'..'۹' -> append('0' + (c - '۰'))
                    else -> append(c)
                }
            }
        }
        // Strip bidi marks, spaces, dashes, brackets and dots WhatsApp uses for formatting.
        val compact = normalized.replace(Regex("[\\s\\u00A0\\u200E\\u200F\\u202A-\\u202E\\u2066-\\u2069()\\-.]"), "")
        if (!Regex("^\\+?\\d{7,15}$").matches(compact)) return null
        if (requirePlus && !compact.startsWith("+")) return null
        val digits = compact.trimStart('+')
        return "+$digits"
    }

    private fun finishScan() {
        if (job != Job.SCAN) return
        val cb = scanCallback
        scanCallback = null
        val result = scanned.toList()
        endJob()
        Log.d(TAG, "Scan finished: ${result.size} numbers")
        cb?.invoke(result)
    }

    // ---------------------------------------------------------------------
    // 2. READ — read one chat for the AI
    // ---------------------------------------------------------------------

    private val readMessages = mutableListOf<Map<String, String>>()
    private val readKeys = HashSet<String>()
    private var readCallback: ((Map<String, Any>) -> Unit)? = null
    private var readAttempts = 0
    private var readPages = 0
    private var readNotOnWhatsApp = false
    private val maxHistoryPages = 4
    private val maxMessages = 80

    fun startRead(phone: String, pkg: String, onDone: (Map<String, Any>) -> Unit) {
        if (isBusy()) { onDone(mapOf("status" to "busy", "messages" to emptyList<Any>())); return }
        beginJob(Job.READ, pkg)
        readCallback = onDone
        readMessages.clear(); readKeys.clear()
        readAttempts = 0; readPages = 0; readNotOnWhatsApp = false

        val digits = phone.filter { it.isDigit() }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$digits")).apply {
            setPackage(pkg)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Cannot open chat: ${e.message}")
            finishRead(); return
        }
        later(30_000) { finishRead() } // hard timeout
        later(2200) { readStep() }
    }

    private fun readStep() {
        val root = waRoot()
        if (root == null || !isConversationScreen(root)) {
            if (root != null && findNotOnWhatsAppDialog(root)) {
                readNotOnWhatsApp = true
                dismissDialog(root)
                finishRead(); return
            }
            if (++readAttempts > 12) { finishRead(); return }
            later(700) { readStep() }
            return
        }

        val page = extractMessages(root)
        if (page.isEmpty() && readPages == 0 && readAttempts < 5) {
            readAttempts++
            later(700) { readStep() } // bubbles not rendered yet
            return
        }

        val fresh = page.filter { m -> readKeys.add("${m["direction"]}|${m["time"]}|${m["text"]}") }
        readMessages.addAll(0, fresh)

        if (page.isEmpty() || readPages >= maxHistoryPages || (readPages > 0 && fresh.isEmpty())) {
            finishRead(); return
        }
        val list = findVerticalList(root)
        if (list?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) != true) swipe(0.30f, 0.75f)
        readPages++
        later(900) { readStep() }
    }

    /** Visible messages top-to-bottom: {text, direction, time}. */
    private fun extractMessages(root: AccessibilityNodeInfo): List<Map<String, String>> {
        val nodes = byId(root, "message_text") + byId(root, "caption")
        val width = resources.displayMetrics.widthPixels
        val rtl = resources.configuration.layoutDirection == View.LAYOUT_DIRECTION_RTL
        val anyTicks = byId(root, "status").isNotEmpty()

        return nodes.mapNotNull { node ->
            val text = node.text?.toString()?.trim().orEmpty()
            if (text.isEmpty()) return@mapNotNull null
            val rect = Rect().also { node.getBoundsInScreen(it) }
            Triple(node, text, rect)
        }.sortedBy { it.third.top }.map { (node, text, rect) ->
            val bubble = bubbleOf(node)
            val time = bubble?.let { byId(it, "date").firstOrNull()?.text?.toString()?.trim() }.orEmpty()
            val hasTick = bubble?.let { byId(it, "status").isNotEmpty() } == true
            val direction = when {
                hasTick -> "out" // only our own messages carry delivery ticks
                anyTicks -> "in"
                else -> if ((rect.centerX() > width / 2) != rtl) "out" else "in"
            }
            mapOf("text" to text, "direction" to direction, "time" to time)
        }
    }

    private fun bubbleOf(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var cur = node.parent
        var depth = 0
        while (cur != null && depth < 5) {
            if (byId(cur, "message_text").size > 1) return null
            if (byId(cur, "date").isNotEmpty()) return cur
            cur = cur.parent
            depth++
        }
        return null
    }

    private fun finishRead() {
        if (job != Job.READ) return
        val cb = readCallback
        readCallback = null
        val msgs = readMessages.takeLast(maxMessages).toList()
        val status = when {
            readNotOnWhatsApp -> "not_on_whatsapp"
            else -> "ok"
        }
        readMessages.clear(); readKeys.clear()
        endJob()
        if (!readNotOnWhatsApp && waRoot() != null) performGlobalAction(GLOBAL_ACTION_BACK) // leave the chat
        cb?.invoke(mapOf("status" to status, "messages" to msgs))
    }

    // ---------------------------------------------------------------------
    // 3. SEND — deliver one message to one number
    // ---------------------------------------------------------------------

    private var sendCallback: ((String) -> Unit)? = null
    private var sendAttempts = 0
    private var sendClicks = 0
    private var sendHasMedia = false
    private var sendClickedAt = 0L

    /**
     * Text only: opens the chat with the text pre-filled, then presses Send.
     * With media: shares the file straight to the chat (WhatsApp "jid" extra),
     * with the text as caption, then presses Send on the preview screen.
     */
    fun startSend(
        phone: String,
        pkg: String,
        text: String,
        mediaPath: String?,
        mimeType: String?,
        onDone: (String) -> Unit,
    ) {
        if (isBusy()) { onDone("busy"); return }
        beginJob(Job.SEND, pkg)
        sendCallback = onDone
        sendAttempts = 0; sendClicks = 0; sendClickedAt = 0
        sendHasMedia = !mediaPath.isNullOrEmpty()
        val digits = phone.filter { it.isDigit() }

        val intent = try {
            if (!sendHasMedia) {
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://api.whatsapp.com/send?phone=$digits&text=${Uri.encode(text)}"),
                )
            } else {
                val file = File(mediaPath!!)
                if (!file.exists()) { finishSend("failed:file_missing"); return }
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                Intent(Intent.ACTION_SEND).apply {
                    type = mimeType ?: "*/*"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    if (text.isNotBlank()) putExtra(Intent.EXTRA_TEXT, text)
                    putExtra("jid", "$digits@s.whatsapp.net")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
        } catch (e: Exception) {
            finishSend("failed:${e.message}"); return
        }
        intent.setPackage(pkg)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        try {
            startActivity(intent)
        } catch (e: Exception) {
            finishSend("failed:cannot_open_whatsapp"); return
        }
        later(45_000) { finishSend("failed:timeout") }
        later(2000) { sendStep() }
    }

    private fun sendStep() {
        val root = waRoot()
        if (root != null && findNotOnWhatsAppDialog(root)) {
            dismissDialog(root)
            finishSend("not_on_whatsapp"); return
        }

        // After a click: confirm the message left the composer.
        if (sendClicks > 0) {
            if (root == null || isSent(root)) { finishSend("sent"); return }
            if (System.currentTimeMillis() - sendClickedAt < 2500) { later(600) { sendStep() }; return }
            if (sendClicks >= 3) { finishSend("failed:send_not_confirmed"); return }
            // Fall through and press Send again.
        }

        val button = root?.let { findSendButton(it) }
        if (button == null || !button.isEnabled) {
            if (++sendAttempts > 30) { finishSend("failed:send_button_not_found"); return }
            later(600) { sendStep() }
            return
        }
        if (click(button)) {
            sendClicks++
            sendClickedAt = System.currentTimeMillis()
        }
        later(1200) { sendStep() }
    }

    private fun isSent(root: AccessibilityNodeInfo): Boolean {
        val stillHasSendButton = findSendButton(root) != null
        if (!stillHasSendButton) return true
        // Text chats: the composer is cleared once the message is sent.
        val entry = byId(root, "entry").firstOrNull() ?: return false
        val value = entry.text?.toString().orEmpty()
        val hint = entry.hintText?.toString().orEmpty()
        return value.isBlank() || value == hint
    }

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        for (id in listOf("send", "send_btn", "send_media_btn")) {
            byId(root, id).firstOrNull { it.isVisibleToUser }?.let { return it }
        }
        // "Send to …?" confirmation dialog used for documents.
        root.findAccessibilityNodeInfosByViewId("android:id/button1").firstOrNull()?.let { btn ->
            val t = btn.text?.toString()?.trim()?.lowercase().orEmpty()
            if (SEND_WORDS.any { t == it || t.startsWith(it) }) return btn
        }
        return findByDescription(root)
    }

    private fun findByDescription(node: AccessibilityNodeInfo?, depth: Int = 0): AccessibilityNodeInfo? {
        if (node == null || depth > 40) return null
        val desc = node.contentDescription?.toString()?.trim()?.lowercase().orEmpty()
        if (desc.isNotEmpty() && node.isVisibleToUser && SEND_WORDS.contains(desc)) return node
        for (i in 0 until node.childCount) findByDescription(node.getChild(i), depth + 1)?.let { return it }
        return null
    }

    private fun finishSend(status: String) {
        if (job != Job.SEND) return
        val cb = sendCallback
        sendCallback = null
        endJob()
        // Close the chat so the next number starts clean.
        // Only while WhatsApp is in front: after a media share it may already have
        // returned to MobiWA, and Back there would close the app's screen.
        if ((status == "sent" || status.startsWith("failed")) && waRoot() != null) {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
        Log.d(TAG, "Send finished: $status")
        cb?.invoke(status)
    }

    // ---------------------------------------------------------------------
    // Floating status pill with a Stop button, shown over WhatsApp
    // ---------------------------------------------------------------------

    private var overlay: View? = null
    private var overlayText: TextView? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    @SuppressLint("SetTextI18n")
    fun showOverlay(message: String) {
        acquireWakeLock()
        if (overlay != null) { updateOverlay(message); return }
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val label = TextView(this).apply {
            text = message
            setTextColor(Color.WHITE)
            textSize = 14f
            setPadding(dp(16), dp(10), dp(12), dp(10))
        }
        val stop = TextView(this).apply {
            text = "STOP"
            setTextColor(Color.WHITE)
            textSize = 13f
            setPadding(dp(14), dp(8), dp(14), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.parseColor("#E5484D"))
            }
            setOnClickListener {
                cancelCurrentJob()
                MainActivity.emit("onStopRequested", null)
                updateOverlay("Stopping…")
            }
        }
        val pill = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), dp(4), dp(6), dp(4))
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.parseColor("#E6111B21"))
            }
            elevation = dp(6).toFloat()
            addView(label)
            addView(stop)
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(96) // above WhatsApp's message bar
        }
        try {
            wm.addView(pill, params)
            overlay = pill
            overlayText = label
        } catch (e: Exception) {
            Log.e(TAG, "Overlay failed: ${e.message}")
        }
    }

    fun updateOverlay(message: String) {
        handler.post { overlayText?.text = message }
    }

    fun hideOverlay() {
        releaseWakeLock()
        val v = overlay ?: return
        overlay = null
        overlayText = null
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {}
    }

    @Suppress("DEPRECATION")
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "MobiWA:automation",
        ).apply { acquire(3 * 60 * 60 * 1000L) }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {}
        wakeLock = null
    }
}
