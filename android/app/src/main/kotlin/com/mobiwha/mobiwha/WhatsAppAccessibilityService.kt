package com.mobiwha.mobiwha

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class WhatsAppAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "WhatsAppA11yService"
        
        var instance: WhatsAppAccessibilityService? = null
            private set

        var isCollecting: Boolean = false
            private set

        var isScrapingChat: Boolean = false
            private set

        private var onCollectFinished: ((List<String>) -> Unit)? = null
        private var onChatScraped: ((List<Map<String, String>>) -> Unit)? = null
        private val collectedRawNumbers = LinkedHashSet<String>()
        private val visibleContentSignatures = HashSet<String>()
        private var scrollCount = 0
        private var stagnantScrolls = 0
        private const val MAX_SCROLLS = 1000
        private const val MAX_STAGNANT = 18

        // How many times we scroll up inside a chat to load older history.
        private const val SCRAPE_HISTORY_PAGES = 4
        // Hard ceiling so the Flutter side never waits forever.
        private const val SCRAPE_TIMEOUT_MS = 30000L
        // Max messages handed back to Flutter per chat.
        private const val SCRAPE_MAX_MESSAGES = 80

        fun isServiceRunning(): Boolean = instance != null

        /**
         * Opens the WhatsApp chat for [phone], reads the visible message bubbles
         * (scrolling up a few pages for history) and returns them oldest-first.
         * Always invokes [onComplete] exactly once, even on failure or timeout.
         */
        fun scrapeCurrentChatMessages(
            phone: String,
            targetPackage: String? = null,
            context: Context,
            onComplete: (List<Map<String, String>>) -> Unit
        ) {
            val service = instance
            if (service == null || isScrapingChat || isCollecting) {
                Log.w(TAG, "Chat scrape skipped (service=${service != null}, busy=${isScrapingChat || isCollecting})")
                onComplete(emptyList())
                return
            }
            service.beginChatScrape(phone, targetPackage, context, onComplete)
        }

        fun startAutoCollecting(
            context: Context,
            targetPackage: String? = null,
            onComplete: (List<String>) -> Unit
        ) {
            collectedRawNumbers.clear()
            visibleContentSignatures.clear()
            scrollCount = 0
            stagnantScrolls = 0
            onCollectFinished = onComplete
            isCollecting = true

            val pm = context.packageManager
            var launchIntent: Intent? = null

            if (!targetPackage.isNullOrEmpty()) {
                launchIntent = pm.getLaunchIntentForPackage(targetPackage)
            }
            if (launchIntent == null) {
                launchIntent = pm.getLaunchIntentForPackage("com.whatsapp.w4b")
                    ?: pm.getLaunchIntentForPackage("com.whatsapp")
            }
            if (launchIntent == null) {
                val pkg = targetPackage ?: "com.whatsapp"
                launchIntent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("whatsapp://app")).apply {
                    setPackage(pkg)
                }
            }

            try {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                context.startActivity(launchIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch WhatsApp: ${e.message}")
                try {
                    val pkg = targetPackage ?: "com.whatsapp"
                    val fallbackIntent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_LAUNCHER)
                        setPackage(pkg)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(fallbackIntent)
                } catch (e2: Exception) {
                    isCollecting = false
                    onComplete(emptyList())
                    return
                }
            }

            instance?.let { s ->
                s.mainHandler.postDelayed({
                    if (isCollecting) {
                        s.handleCollectingEvent()
                    }
                }, 1500)
            }
        }

        fun stopAutoCollecting(context: Context?) {
            if (!isCollecting) return
            isCollecting = false
            val results = collectedRawNumbers.toList()
            val callback = onCollectFinished
            onCollectFinished = null

            // Bring MobiWA back to foreground
            context?.let { ctx ->
                try {
                    val returnIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    }
                    if (returnIntent != null) {
                        ctx.startActivity(returnIntent)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Could not return to MobiWA: ${e.message}")
                }
            }

            callback?.invoke(results)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isProcessingStep = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "WhatsAppAccessibilityService connected.")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        isCollecting = false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return
        if (packageName != "com.whatsapp" && packageName != "com.whatsapp.w4b") return

        // Chat reading is driven by its own timed steps; never auto-click while reading.
        if (isScrapingChat) return

        if (isCollecting) {
            handleCollectingEvent()
            return
        }

        // Give WhatsApp a moment to settle after a chat read before auto-send may act.
        if (System.currentTimeMillis() - lastScrapeFinishedAt < 4000) return
        handleAutoSendEvent()
    }

    // ---------------------------------------------------------------------
    // Chat reading (used by Mobi AI)
    // ---------------------------------------------------------------------

    private val scrapedChat = mutableListOf<Map<String, String>>()
    private val scrapedKeys = HashSet<String>()
    private var scrapeWaitAttempts = 0
    private var scrapeHistoryPages = 0
    private var scrapeTimeoutRunnable: Runnable? = null
    private var lastScrapeFinishedAt = 0L

    private fun beginChatScrape(
        phone: String,
        targetPackage: String?,
        context: Context,
        onComplete: (List<Map<String, String>>) -> Unit
    ) {
        onChatScraped = onComplete
        isScrapingChat = true
        scrapedChat.clear()
        scrapedKeys.clear()
        scrapeWaitAttempts = 0
        scrapeHistoryPages = 0

        val cleanPhone = phone.filter { it.isDigit() }
        val pkg = resolveWhatsAppPackage(targetPackage)
        val uri = android.net.Uri.parse("https://wa.me/$cleanPhone")
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            if (pkg != null) setPackage(pkg)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open chat for reading: ${e.message}")
            finishChatScraping(pressBack = false)
            return
        }

        val timeout = Runnable {
            Log.w(TAG, "Chat read timed out; returning ${scrapedChat.size} messages.")
            finishChatScraping()
        }
        scrapeTimeoutRunnable = timeout
        mainHandler.postDelayed(timeout, SCRAPE_TIMEOUT_MS)
        mainHandler.postDelayed({ handleChatScrapingStep() }, 2500)
    }

    private fun resolveWhatsAppPackage(requested: String?): String? {
        val candidates = listOfNotNull(requested?.takeIf { it.isNotBlank() }) +
            listOf("com.whatsapp.w4b", "com.whatsapp")
        return candidates.firstOrNull { pkg ->
            try {
                packageManager.getPackageInfo(pkg, 0)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun handleChatScrapingStep() {
        if (!isScrapingChat) return
        try {
            val root = rootInActiveWindow
            val rootPkg = root?.packageName?.toString()
            if (root == null || (rootPkg != "com.whatsapp" && rootPkg != "com.whatsapp.w4b")) {
                retryChatWaitOrFinish()
                return
            }

            if (!isConversationScreen(root, rootPkg)) {
                // wa.me for a number without WhatsApp shows a dialog instead of a chat.
                if (isNotOnWhatsAppDialog(root)) {
                    Log.d(TAG, "Number is not on WhatsApp; nothing to read.")
                    finishChatScraping()
                    return
                }
                retryChatWaitOrFinish()
                return
            }

            val page = extractMessagesFromChatScreen(root, rootPkg)
            if (page.isEmpty() && scrapeHistoryPages == 0 && scrapeWaitAttempts < 4) {
                // Conversation is open but bubbles have not rendered yet.
                scrapeWaitAttempts++
                mainHandler.postDelayed({ handleChatScrapingStep() }, 700)
                return
            }

            val added = mergeOlderPage(page)
            Log.d(TAG, "Chat page ${scrapeHistoryPages}: +$added (total ${scrapedChat.size})")

            if (page.isEmpty() || scrapeHistoryPages >= SCRAPE_HISTORY_PAGES ||
                (scrapeHistoryPages > 0 && added == 0)
            ) {
                finishChatScraping()
                return
            }

            // Scroll up to load older messages.
            val list = findVerticalScrollableList(root)
            val scrolled = list?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) ?: false
            if (!scrolled) performSwipeDownGesture()
            scrapeHistoryPages++
            mainHandler.postDelayed({ handleChatScrapingStep() }, 900)
        } catch (e: Exception) {
            Log.e(TAG, "Error during chat reading: ${e.message}", e)
            finishChatScraping()
        }
    }

    private fun retryChatWaitOrFinish() {
        if (scrapeWaitAttempts < 10) {
            scrapeWaitAttempts++
            mainHandler.postDelayed({ handleChatScrapingStep() }, 700)
        } else {
            finishChatScraping()
        }
    }

    private fun isConversationScreen(root: AccessibilityNodeInfo, pkg: String): Boolean {
        val markers = arrayOf("entry", "conversation_contact_name", "message_text", "conversation_root_layout")
        return markers.any { id -> root.findAccessibilityNodeInfosByViewId("$pkg:id/$id").isNotEmpty() }
    }

    private fun isNotOnWhatsAppDialog(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        val text = node.text?.toString()?.lowercase().orEmpty()
        if (text.isNotEmpty()) {
            if ((text.contains("on whatsapp") && (text.contains("isn't") || text.contains("is not") || text.contains("not on"))) ||
                text.contains("url is invalid") ||
                text.contains("غير موجود على واتساب") ||
                text.contains("ليس على واتساب")
            ) return true
        }
        for (i in 0 until node.childCount) {
            if (isNotOnWhatsAppDialog(node.getChild(i))) return true
        }
        return false
    }

    /** Prepends messages from an older (scrolled-up) page that we have not seen yet. */
    private fun mergeOlderPage(page: List<Map<String, String>>): Int {
        val fresh = page.filter { m ->
            val key = "${m["direction"]}|${m["time"]}|${m["message"]}"
            scrapedKeys.add(key)
        }
        scrapedChat.addAll(0, fresh)
        return fresh.size
    }

    private fun finishChatScraping(pressBack: Boolean = true) {
        if (!isScrapingChat) return
        isScrapingChat = false
        scrapeTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        scrapeTimeoutRunnable = null
        lastScrapeFinishedAt = System.currentTimeMillis()

        val callback = onChatScraped
        onChatScraped = null

        val kept = scrapedChat.takeLast(SCRAPE_MAX_MESSAGES)
        val base = System.currentTimeMillis() - kept.size * 1000L
        val results = kept.mapIndexed { index, m ->
            mapOf(
                "message" to (m["message"] ?: ""),
                "direction" to (m["direction"] ?: "incoming"),
                "time" to (m["time"] ?: ""),
                // Synthetic but strictly ordered timestamps (WhatsApp only shows hh:mm).
                "timestamp" to (base + index * 1000L).toString()
            )
        }
        scrapedChat.clear()
        scrapedKeys.clear()

        // Leave the chat while WhatsApp is still in front, then bring MobiWA back.
        if (pressBack) performGlobalAction(GLOBAL_ACTION_BACK)
        mainHandler.postDelayed({
            try {
                val returnIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                if (returnIntent != null) startActivity(returnIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Error returning to MobiWA after chat read: ${e.message}")
            }
        }, 350)

        Log.d(TAG, "Chat read finished with ${results.size} messages.")
        callback?.invoke(results)
    }

    /** Returns the visible chat messages, top-to-bottom. */
    private fun extractMessagesFromChatScreen(root: AccessibilityNodeInfo, pkg: String): List<Map<String, String>> {
        val textNodes = root.findAccessibilityNodeInfosByViewId("$pkg:id/message_text") +
            root.findAccessibilityNodeInfosByViewId("$pkg:id/caption")
        if (textNodes.isEmpty()) {
            val generic = mutableListOf<Map<String, String>>()
            extractGenericChatText(root, generic)
            return generic
        }

        val anyStatusOnScreen = root.findAccessibilityNodeInfosByViewId("$pkg:id/status").isNotEmpty()
        val screenWidth = resources.displayMetrics.widthPixels
        val isRtl = resources.configuration.layoutDirection == View.LAYOUT_DIRECTION_RTL

        val withBounds = textNodes.mapNotNull { node ->
            val text = node.text?.toString()?.trim().orEmpty()
            if (text.isEmpty()) return@mapNotNull null
            val rect = Rect()
            node.getBoundsInScreen(rect)
            Triple(node, text, rect)
        }.sortedBy { it.third.top }

        return withBounds.map { (node, text, rect) ->
            val bubble = findBubbleContainer(node, pkg)
            val time = bubble?.findAccessibilityNodeInfosByViewId("$pkg:id/date")
                ?.firstOrNull()?.text?.toString()?.trim().orEmpty()
            val hasTick = bubble?.findAccessibilityNodeInfosByViewId("$pkg:id/status")?.isNotEmpty() == true
            val direction = when {
                hasTick -> "outgoing" // Only our own messages show delivery ticks.
                anyStatusOnScreen -> "incoming"
                else -> {
                    val onRight = rect.centerX() > screenWidth / 2
                    if (onRight != isRtl) "outgoing" else "incoming"
                }
            }
            mapOf("message" to text, "direction" to direction, "time" to time)
        }
    }

    /** Walks up from a message text node to its bubble (the node that also holds the time). */
    private fun findBubbleContainer(node: AccessibilityNodeInfo, pkg: String): AccessibilityNodeInfo? {
        var current = node.parent
        var depth = 0
        while (current != null && depth < 5) {
            if (current.findAccessibilityNodeInfosByViewId("$pkg:id/message_text").size > 1) return null
            if (current.findAccessibilityNodeInfosByViewId("$pkg:id/date").isNotEmpty()) return current
            current = current.parent
            depth++
        }
        return null
    }

    /** Fallback for WhatsApp builds without the usual view ids. Skips the header and input bar. */
    private fun extractGenericChatText(node: AccessibilityNodeInfo?, output: MutableList<Map<String, String>>) {
        if (node == null) return
        val viewId = node.viewIdResourceName?.lowercase() ?: ""
        val skipIds = arrayOf("toolbar", "action_bar", "conversation_contact", "contact_name",
            "contact_status", "entry", "footer", "input")
        if (skipIds.any { viewId.contains(it) }) return

        val className = node.className?.toString() ?: ""
        val text = node.text?.toString()?.trim().orEmpty()
        if (text.length > 1 && className.contains("TextView") && !className.contains("EditText")) {
            val lower = text.lowercase()
            val isIgnoredUI = lower == "today" || lower == "yesterday" || lower == "online" ||
                lower == "typing..." || lower.contains("end-to-end encrypted") ||
                lower.contains("disappearing messages") || lower.contains("messages and calls") ||
                text.matches(Regex("^[0-9]{1,2}:[0-9]{2}(\\s*(AM|PM|am|pm|ص|م))?$"))
            if (!isIgnoredUI && (output.isEmpty() || output.last()["message"] != text)) {
                val rect = Rect()
                node.getBoundsInScreen(rect)
                val onRight = rect.centerX() > resources.displayMetrics.widthPixels / 2
                val isRtl = resources.configuration.layoutDirection == View.LAYOUT_DIRECTION_RTL
                output.add(mapOf(
                    "message" to text,
                    "direction" to if (onRight != isRtl) "outgoing" else "incoming",
                    "time" to ""
                ))
            }
        }
        for (i in 0 until node.childCount) {
            extractGenericChatText(node.getChild(i), output)
        }
    }

    private fun performSwipeDownGesture() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val metrics = resources.displayMetrics
            val x = metrics.widthPixels / 2f
            val path = Path().apply {
                moveTo(x, metrics.heightPixels * 0.30f)
                lineTo(x, metrics.heightPixels * 0.75f)
            }
            val gesture = GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, 250))
                .build()
            dispatchGesture(gesture, null, null)
        }
    }

    private fun handleCollectingEvent() {
        if (isProcessingStep) return
        isProcessingStep = true

        mainHandler.postDelayed({
            try {
                processChatListCrawlerStep()
            } catch (e: Exception) {
                Log.e(TAG, "Error in collection step: ${e.message}", e)
            } finally {
                isProcessingStep = false
            }
        }, 400)
    }

    private fun processChatListCrawlerStep() {
        if (!isCollecting) return
        val rootNode = rootInActiveWindow ?: return

        // Extract all visible numbers and generate a screen signature
        val beforeCount = collectedRawNumbers.size
        val screenSignature = StringBuilder()
        extractPhoneNumbersFromNode(rootNode, screenSignature)
        val afterCount = collectedRawNumbers.size
        val newNumbersFound = afterCount - beforeCount

        val sigStr = screenSignature.toString()
        val isNewScreenContent = sigStr.isNotEmpty() && visibleContentSignatures.add(sigStr)

        if (!isNewScreenContent && newNumbersFound == 0) {
            stagnantScrolls++
        } else {
            stagnantScrolls = 0
        }

        scrollCount++
        Log.d(TAG, "Chat scroll #$scrollCount | New numbers: $newNumbersFound | Total: ${collectedRawNumbers.size} | Stagnant: $stagnantScrolls")

        // Stop only when reaching the true bottom (maximum vertical scroll reach) or max limit
        if (scrollCount >= MAX_SCROLLS || stagnantScrolls >= MAX_STAGNANT) {
            Log.d(TAG, "Reached end of vertical chats scroll. Total unsaved numbers: ${collectedRawNumbers.size}")
            stopAutoCollecting(this)
            return
        }

        // Strictly scroll vertically down on the first tab
        scrollVerticalOnly(rootNode)

        // Schedule next inspection and scroll
        mainHandler.postDelayed({
            if (isCollecting) {
                handleCollectingEvent()
            }
        }, 550)
    }

    private fun scrollVerticalOnly(rootNode: AccessibilityNodeInfo) {
        val verticalList = findVerticalScrollableList(rootNode)
        var scrolled = false
        if (verticalList != null) {
            scrolled = verticalList.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
        }
        if (!scrolled) {
            // Strictly vertical swipe gesture from bottom to top in the exact center
            performSwipeUpGesture()
        }
    }

    private fun findVerticalScrollableList(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        val className = node.className?.toString() ?: ""

        // Skip horizontal ViewPager / TabLayout to prevent accidental tab flipping
        if (className.contains("ViewPager", ignoreCase = true) ||
            className.contains("HorizontalScrollView", ignoreCase = true) ||
            className.contains("TabLayout", ignoreCase = true) ||
            className.contains("TabBar", ignoreCase = true)) {
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                val found = findVerticalScrollableList(child)
                if (found != null) return found
            }
            return null
        }

        if (node.isScrollable && (className.contains("RecyclerView") || className.contains("ListView") || className.contains("ScrollView"))) {
            return node
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            val found = findVerticalScrollableList(child)
            if (found != null) return found
        }
        return null
    }

    private fun extractPhoneNumbersFromNode(node: AccessibilityNodeInfo?, signatureBuilder: StringBuilder? = null) {
        if (node == null) return

        val text = node.text?.toString()?.trim()
        val contentDesc = node.contentDescription?.toString()?.trim()

        if (!text.isNullOrEmpty()) {
            signatureBuilder?.append(text)?.append("|")
            checkAndAddPhoneNumber(text)
        }
        if (!contentDesc.isNullOrEmpty() && contentDesc != text) {
            signatureBuilder?.append(contentDesc)?.append("|")
            checkAndAddPhoneNumber(contentDesc)
        }

        val childCount = node.childCount
        for (i in 0 until childCount) {
            val child = node.getChild(i)
            extractPhoneNumbersFromNode(child, signatureBuilder)
        }
    }

    private val phoneRegex = Regex("""(\+?[0-9]{1,4}[\s\-]?[0-9]{1,4}[\s\-]?[0-9]{2,4}[\s\-]?[0-9]{2,5})""")

    private fun checkAndAddPhoneNumber(raw: String) {
        val clean = raw.trim()
        if (clean.isEmpty()) return

        val digitCount = clean.count { it.isDigit() }
        val hasLetters = clean.any { it.isLetter() }

        // Primary case: pure phone number string in chat list (unsaved contact title)
        if (digitCount in 7..16 && !hasLetters) {
            // Filter out time strings like 10:45 or dates like 12/05/2024
            if (!clean.contains(":") && !clean.contains("/") && !clean.contains("AM", ignoreCase = true) && !clean.contains("PM", ignoreCase = true)) {
                if (clean.startsWith("+") || clean.startsWith("0") || clean.startsWith("(") || clean.first().isDigit()) {
                    collectedRawNumbers.add(clean)
                    Log.d(TAG, "Collected unsaved number: $clean (Total: ${collectedRawNumbers.size})")
                    return
                }
            }
        }

        // Secondary regex match for numbers starting with '+' or country codes
        val match = phoneRegex.find(clean)
        if (match != null) {
            val matchedPhone = match.value.trim()
            val mDigits = matchedPhone.count { it.isDigit() }
            if (mDigits in 7..16 && (matchedPhone.startsWith("+") || matchedPhone.startsWith("00"))) {
                collectedRawNumbers.add(matchedPhone)
                Log.d(TAG, "Extracted regex number: $matchedPhone (Total: ${collectedRawNumbers.size})")
            }
        }
    }

    private fun performSwipeUpGesture() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val displayMetrics = DisplayMetrics()
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getMetrics(displayMetrics)

            val width = displayMetrics.widthPixels.toFloat()
            val height = displayMetrics.heightPixels.toFloat()

            // Exact center vertical swipe: startX == endX
            val startX = width / 2f
            val startY = height * 0.75f
            val endX = width / 2f
            val endY = height * 0.25f

            val swipePath = Path().apply {
                moveTo(startX, startY)
                lineTo(endX, endY)
            }

            val gestureBuilder = GestureDescription.Builder()
            gestureBuilder.addStroke(GestureDescription.StrokeDescription(swipePath, 0, 200))
            dispatchGesture(gestureBuilder.build(), null, null)
        }
    }

    private var lastSendClickTime: Long = 0

    private fun handleAutoSendEvent() {
        val rootNode = rootInActiveWindow ?: return
        val now = System.currentTimeMillis()
        if (now - lastSendClickTime < 2500) return // Debounce send clicks

        val sendButton = findSendButton(rootNode) ?: return

        var clickTarget: AccessibilityNodeInfo? = sendButton
        while (clickTarget != null && !clickTarget.isClickable) {
            clickTarget = clickTarget.parent
        }
        if (clickTarget == null) clickTarget = sendButton

        val clicked = clickTarget.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        if (clicked) {
            lastSendClickTime = now
            Log.d(TAG, "Auto-pressed WhatsApp send button successfully.")

            // Wait 700ms for WhatsApp to send, then return to MobiWA
            mainHandler.postDelayed({
                // Bring MobiWA to front
                try {
                    val returnIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    }
                    if (returnIntent != null) {
                        startActivity(returnIntent)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error launching return intent: ${e.message}")
                }
                // Also trigger back action as backup
                mainHandler.postDelayed({
                    performGlobalAction(GLOBAL_ACTION_BACK)
                }, 250)
            }, 700)
        }
    }

    private fun findSendButton(rootNode: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // 1. Check known view IDs
        val knownIds = arrayOf(
            "com.whatsapp:id/send",
            "com.whatsapp.w4b:id/send",
            "send"
        )
        for (id in knownIds) {
            val list = rootNode.findAccessibilityNodeInfosByViewId(id)
            if (list.isNotEmpty()) {
                val candidate = list.firstOrNull { it.isVisibleToUser } ?: list.first()
                return candidate
            }
        }

        // 2. Search recursively by content descriptions across languages
        return searchSendButtonRecursively(rootNode)
    }

    private fun searchSendButtonRecursively(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null

        val desc = node.contentDescription?.toString()?.trim()?.lowercase() ?: ""

        // Multi-language send keywords. Match the button's content description only;
        // matching visible text would click chat bubbles that merely contain "send".
        val sendKeywords = arrayOf("send", "إرسال", "enviar", "envoyer", "senden", "invia", "отправить")
        for (kw in sendKeywords) {
            if (desc.contains(kw)) {
                return node
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            val found = searchSendButtonRecursively(child)
            if (found != null) return found
        }
        return null
    }

    override fun onInterrupt() {
        isCollecting = false
    }
}

