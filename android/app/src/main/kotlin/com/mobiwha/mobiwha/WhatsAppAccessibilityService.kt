package com.mobiwha.mobiwha

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
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

        fun isServiceRunning(): Boolean = instance != null

        fun scrapeCurrentChatMessages(
            phone: String,
            targetPackage: String? = null,
            context: Context,
            onComplete: (List<Map<String, String>>) -> Unit
        ) {
            onChatScraped = onComplete
            isScrapingChat = true

            // Open chat in WhatsApp via Intent
            val cleanPhone = phone.filter { it.isDigit() }
            val uri = android.net.Uri.parse("https://wa.me/$cleanPhone")
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                if (!targetPackage.isNullOrEmpty()) {
                    setPackage(targetPackage)
                }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }

            try {
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to open chat for scraping: ${e.message}")
                isScrapingChat = false
                onComplete(emptyList())
                return
            }

            instance?.let { s ->
                s.mainHandler.postDelayed({
                    if (isScrapingChat) {
                        s.handleChatScrapingStep()
                    }
                }, 3500)
            }
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

        if (isCollecting) {
            handleCollectingEvent()
        } else if (!isScrapingChat) {
            handleAutoSendEvent()
        }
    }

    private var scrapeRetryCount = 0

    private fun handleChatScrapingStep() {
        if (!isScrapingChat) return

        mainHandler.postDelayed({
            try {
                val rootNode = rootInActiveWindow
                if (rootNode == null) {
                    if (scrapeRetryCount < 3) {
                        scrapeRetryCount++
                        Log.d(TAG, "Scrape rootNode null, retrying ($scrapeRetryCount/3)...")
                        mainHandler.postDelayed({ handleChatScrapingStep() }, 600)
                        return@postDelayed
                    }
                    finishChatScraping(emptyList())
                    return@postDelayed
                }

                val messages = mutableListOf<Map<String, String>>()
                extractMessagesFromChatScreen(rootNode, messages)

                if (messages.isEmpty() && scrapeRetryCount < 3) {
                    scrapeRetryCount++
                    Log.d(TAG, "No messages extracted yet, retrying ($scrapeRetryCount/3)...")
                    mainHandler.postDelayed({ handleChatScrapingStep() }, 700)
                    return@postDelayed
                }

                // Limit to last 20 messages
                val finalMessages = if (messages.size > 20) {
                    messages.takeLast(20)
                } else {
                    messages
                }

                Log.d(TAG, "Successfully scraped ${finalMessages.size} messages from active WhatsApp chat.")
                finishChatScraping(finalMessages)
            } catch (e: Exception) {
                Log.e(TAG, "Error during chat scraping: ${e.message}", e)
                finishChatScraping(emptyList())
            }
        }, 1200)
    }

    private fun finishChatScraping(messages: List<Map<String, String>>) {
        if (!isScrapingChat) return
        isScrapingChat = false
        scrapeRetryCount = 0
        val callback = onChatScraped
        onChatScraped = null

        // Return to MobiWA immediately
        try {
            val returnIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
            if (returnIntent != null) {
                startActivity(returnIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error returning to MobiWA from scrape: ${e.message}")
        }

        // Close chat window by pressing back
        mainHandler.postDelayed({
            performGlobalAction(GLOBAL_ACTION_BACK)
        }, 300)

        callback?.invoke(messages)
    }

    private fun extractMessagesFromChatScreen(node: AccessibilityNodeInfo?, output: MutableList<Map<String, String>>) {
        if (node == null) return

        val text = node.text?.toString()?.trim()
        val contentDesc = node.contentDescription?.toString()?.trim()
        val viewId = node.viewIdResourceName?.lowercase() ?: ""
        val className = node.className?.toString() ?: ""

        val rawContent = if (!text.isNullOrEmpty()) text else if (!contentDesc.isNullOrEmpty()) contentDesc else ""

        // Skip input edit texts, buttons, and layout containers without text
        val isInputBox = className.contains("EditText", ignoreCase = true) || viewId.contains("entry")
        
        if (rawContent.isNotEmpty() && rawContent.length > 1 && !isInputBox) {
            val lower = rawContent.lowercase()
            val isIgnoredUI = lower == "type a message" ||
                              lower == "message" ||
                              lower == "whatsapp" ||
                              lower == "online" ||
                              lower == "typing..." ||
                              lower == "today" ||
                              lower == "yesterday" ||
                              lower.contains("end-to-end encrypted") ||
                              lower.contains("disappearing messages") ||
                              lower.contains("messages and calls") ||
                              rawContent.matches(Regex("^[0-9]{1,2}:[0-9]{2}(\\s*(AM|PM|am|pm))?$")) // Time only

            if (!isIgnoredUI) {
                var direction = "incoming"
                val desc = (contentDesc ?: "").lowercase()
                val parentId = node.parent?.viewIdResourceName?.lowercase() ?: ""
                
                if (desc.contains("you:") || desc.contains("sent") || viewId.contains("outgoing") || parentId.contains("outgoing") || viewId.contains("sender")) {
                    direction = "outgoing"
                }

                // Avoid exact duplicate consecutive captures
                if (output.isEmpty() || output.last()["message"] != rawContent) {
                    output.add(mapOf(
                        "message" to rawContent,
                        "direction" to direction,
                        "timestamp" to System.currentTimeMillis().toString()
                    ))
                }
            }
        }

        for (i in 0 until node.childCount) {
            extractMessagesFromChatScreen(node.getChild(i), output)
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
        val text = node.text?.toString()?.trim()?.lowercase() ?: ""

        // Multi-language send keywords
        val sendKeywords = arrayOf("send", "إرسال", "enviar", "envoyer", "senden", "invia", "отправить")
        for (kw in sendKeywords) {
            if (desc.contains(kw) || text.contains(kw)) {
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

