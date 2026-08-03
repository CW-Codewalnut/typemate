package com.codewalnut.typemate

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Display
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import io.flutter.plugin.common.MethodChannel

/**
 * The floating mic: dictation without switching keyboards. When any app's
 * editable text field gains focus, a mic bubble appears at the screen
 * edge alongside the user's regular keyboard. Tap it to start - the
 * bubble expands into the listening pill (the desktop overlay's mobile
 * twin) - and tap again to stop; the transcript is inserted into the
 * focused field through the accessibility node (SET_TEXT, clipboard-
 * paste fallback). On a physical keyboard (DeX, Android desktop mode)
 * holding Ctrl+Meta dictates exactly like the desktop app.
 *
 * Drawn as a TYPE_ACCESSIBILITY_OVERLAY on whichever DISPLAY the focused
 * field is on, so no "display over other apps" permission is involved;
 * the one-time setup is enabling this service under system Accessibility
 * settings. Speech runs on the shared on-device engine
 * ([SpeechEngineHolder]).
 */
class TypeMateAccessibilityService : AccessibilityService() {

    private var channel: MethodChannel? = null
    private var bubble: LinearLayout? = null
    private var bubbleLabel: TextView? = null
    private var bubbleIcon: ImageView? = null
    private var bubbleActivePanel: LinearLayout? = null
    private val bubbleBars = mutableListOf<View>()
    private val barAnimators = mutableListOf<android.animation.ObjectAnimator>()
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var bubbleWindowManager: WindowManager? = null
    private var bubbleDisplayId = Display.DEFAULT_DISPLAY
    private var bubbleSize = 0
    private var bubbleDisplayWidth = 0
    private var bubbleDisplayHeight = 0
    private var bubbleShown = false
    private var dictating = false
    private var transcribing = false
    private var ctrlHeld = false
    private var metaHeld = false

    // Drag state: moving past touch slop turns the gesture into a drag;
    // releasing within it is the tap that toggles dictation.
    private var draggingBubble = false
    private var touchDownRawX = 0f
    private var touchDownRawY = 0f
    private var dragStartX = 0
    private var dragStartY = 0

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    private companion object {
        // Upper bound for a transcription round trip before the bubble
        // un-wedges itself (recorder-stop + transcribe timeouts on the
        // Dart side are well under this).
        const val TRANSCRIBE_WATCHDOG_MS = 40_000L
        val MIC_IDLE = Color.parseColor("#E6DEDCF9")
        val INK = Color.parseColor("#3A3A56")

        // The desktop overlay's palette: near-black pill, light text,
        // periwinkle waveform bars.
        val OVERLAY_DARK = Color.parseColor("#F21F1F2A")
        val OVERLAY_TEXT = Color.parseColor("#E8E8F0")
        val OVERLAY_BAR = Color.parseColor("#7B86F8")
        // The desktop failure toast's red pill; same auto-hide.
        val ERROR_PILL = Color.parseColor("#601C22")
        const val ERROR_PILL_MS = 4_500L
        const val BAR_COUNT = 7
        const val BUBBLE_SIZE_DP = 56
        const val BUBBLE_MARGIN_DP = 8
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        channel = SpeechEngineHolder.acquire(this)
    }

    override fun onDestroy() {
        hideBubble()
        removeErrorPill()
        channel = null
        SpeechEngineHolder.release()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        updateBubbleVisibility()
    }

    override fun onInterrupt() {
        if (!dictating) {
            hideBubble()
        }
    }

    /// The bubble follows input focus: visible while an editable field in
    /// another app is focused, gone otherwise, and always on the DISPLAY
    /// that field is on (DeX / Android desktop mode runs apps on the
    /// external monitor while the default display is the handset). Never
    /// yanked away mid-dictation.
    private fun updateBubbleVisibility() {
        if (dictating || transcribing) {
            return
        }
        val focused = focusedEditableNode()
        val ownApp =
            rootInActiveWindow?.packageName == packageName
        if (focused != null && !ownApp) {
            val displayId = displayIdOf(focused)
            if (bubbleShown && bubbleDisplayId != displayId) {
                hideBubble()
            }
            showBubble(displayId)
        } else {
            hideBubble()
        }
    }

    private fun focusedEditableNode(): AccessibilityNodeInfo? {
        val node =
            rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                ?: return null
        // Never over a password field: the bubble must not appear there,
        // and reading its masked text to append would replace the real
        // password with bullets plus the transcript.
        return if (node.isEditable && !node.isPassword) node else null
    }

    private fun displayIdOf(node: AccessibilityNodeInfo): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val id = node.window?.displayId
            if (id != null) {
                return id
            }
        }
        return Display.DEFAULT_DISPLAY
    }

    /// A context whose WindowManager targets [displayId]. Overlays on
    /// secondary displays need a window context (API 31+); older devices
    /// fall back to the default display.
    private fun overlayContextFor(displayId: Int): Context {
        if (displayId == Display.DEFAULT_DISPLAY ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
        ) {
            return this
        }
        val display =
            (getSystemService(DISPLAY_SERVICE) as DisplayManager)
                .getDisplay(displayId) ?: return this
        return createDisplayContext(display).createWindowContext(
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            null,
        )
    }

    private fun showBubble(displayId: Int) {
        if (bubbleShown) {
            return
        }
        val overlayContext = overlayContextFor(displayId)
        val density = overlayContext.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        val size = dp(BUBBLE_SIZE_DP)

        val icon = ImageView(overlayContext).apply {
            setImageResource(android.R.drawable.ic_btn_speak_now)
        }
        val label = TextView(overlayContext).apply {
            textSize = 13f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setTextColor(OVERLAY_TEXT)
            maxLines = 1
            // Centered like every other platform's overlay text.
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
        }
        val barsRow = LinearLayout(overlayContext).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        bubbleBars.clear()
        repeat(BAR_COUNT) { index ->
            val bar = View(overlayContext).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(2).toFloat()
                    setColor(OVERLAY_BAR)
                }
            }
            barsRow.addView(
                bar,
                LinearLayout.LayoutParams(dp(4), dp(16)).apply {
                    marginStart = if (index == 0) 0 else dp(3)
                },
            )
            bubbleBars.add(bar)
        }
        val activePanel = LinearLayout(overlayContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            addView(label)
            addView(
                barsRow,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { topMargin = dp(7) },
            )
        }
        val pill = LinearLayout(overlayContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            minimumWidth = size
            minimumHeight = size
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = size / 2f
                setColor(MIC_IDLE)
            }
            setPadding(dp(14), dp(10), dp(14), dp(10))
            contentDescription = "Tap to dictate"
            addView(icon)
            addView(activePanel)
            setOnTouchListener { view, event -> onMicTouch(view, event) }
        }

        bubbleSize = size
        bubbleDisplayWidth = overlayContext.resources.displayMetrics.widthPixels
        bubbleDisplayHeight =
            overlayContext.resources.displayMetrics.heightPixels

        val preferences =
            getSharedPreferences("typemate_bubble", MODE_PRIVATE)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            // Wherever the user last dragged it (per display, since a
            // monitor and a handset share no geometry); default is the
            // right edge in the upper half, clear of keyboard and field.
            // Clamped so a stored off-screen position (e.g. after a display
            // change) still comes back on-screen.
            x = clampBubbleX(preferences.getInt("x-$displayId", dp(BUBBLE_MARGIN_DP)))
            y = clampBubbleY(
                preferences.getInt("y-$displayId", -(bubbleDisplayHeight / 5)),
            )
        }
        val windowManager =
            overlayContext.getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager.addView(pill, params)
        bubbleWindowManager = windowManager
        bubbleDisplayId = displayId
        bubbleParams = params
        bubble = pill
        bubbleLabel = label
        bubbleIcon = icon
        bubbleActivePanel = activePanel
        bubbleShown = true
        renderBubbleState()
        // Load the model while the user is looking at the field, so the
        // first dictation does not pay the cold start.
        channel?.invokeMethod("warmUp", null)
    }

    private fun hideBubble() {
        val pill = bubble ?: return
        val windowManager = bubbleWindowManager
        stopBarAnimation()
        bubble = null
        bubbleLabel = null
        bubbleIcon = null
        bubbleActivePanel = null
        bubbleBars.clear()
        bubbleParams = null
        bubbleWindowManager = null
        bubbleShown = false
        try {
            windowManager?.removeView(pill)
        } catch (_: IllegalArgumentException) {
            // Already detached (service torn down while hiding).
        }
    }

    /// One source of truth for the bubble's look: the idle mic circle, or
    /// the desktop overlay's twin - a dark pill with the status line and
    /// the animated waveform bars.
    private fun renderBubbleState() {
        val pill = bubble ?: return
        val label = bubbleLabel ?: return
        val icon = bubbleIcon ?: return
        val activePanel = bubbleActivePanel ?: return
        val active = dictating || transcribing
        val density = pill.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        (pill.background as? GradientDrawable)?.apply {
            setColor(if (active) OVERLAY_DARK else MIC_IDLE)
            cornerRadius = dp(if (active) 22 else BUBBLE_SIZE_DP / 2).toFloat()
        }
        icon.setColorFilter(INK)
        icon.visibility = if (active) View.GONE else View.VISIBLE
        label.text = when {
            dictating -> "TypeMate is listening..."
            else -> "Transcribing locally..."
        }
        activePanel.visibility = if (active) View.VISIBLE else View.GONE
        if (active) {
            pill.setPadding(dp(20), dp(12), dp(20), dp(12))
            startBarAnimation()
        } else {
            pill.setPadding(dp(14), dp(10), dp(14), dp(10))
            stopBarAnimation()
        }
        // Wrap-content overlay windows do not reliably grow when their
        // content changes; give the active pill an explicit width and
        // push the new size to the window manager.
        bubbleParams?.let { params ->
            params.width = if (active) {
                dp(220)
            } else {
                WindowManager.LayoutParams.WRAP_CONTENT
            }
            params.height = WindowManager.LayoutParams.WRAP_CONTENT
            try {
                bubbleWindowManager?.updateViewLayout(pill, params)
            } catch (_: IllegalArgumentException) {
                // The window is mid-teardown; the next show re-adds it.
            }
        }
        pill.contentDescription =
            if (dictating) "Tap to stop dictating" else "Tap to dictate"
    }

    /// The desktop overlay's bouncing waveform, approximated: staggered
    /// bars breathing between short and tall.
    private fun startBarAnimation() {
        if (barAnimators.isNotEmpty()) {
            return
        }
        bubbleBars.forEachIndexed { index, bar ->
            val animator =
                android.animation.ObjectAnimator.ofFloat(
                    bar,
                    View.SCALE_Y,
                    0.3f,
                    1f,
                ).apply {
                    duration = 260L + (index % 3) * 60L
                    repeatCount = android.animation.ValueAnimator.INFINITE
                    repeatMode = android.animation.ValueAnimator.REVERSE
                    startDelay = index * 70L
                    start()
                }
            barAnimators.add(animator)
        }
    }

    private fun stopBarAnimation() {
        for (animator in barAnimators) {
            animator.cancel()
        }
        barAnimators.clear()
        for (bar in bubbleBars) {
            bar.scaleY = 1f
        }
    }

    // x is the inset from the END (right) edge: 0 at the edge, up to the
    // display width minus the bubble at the far side.
    private fun clampBubbleX(x: Int): Int =
        x.coerceIn(0, (bubbleDisplayWidth - bubbleSize).coerceAtLeast(0))

    // y offsets from vertical center, so it clamps symmetrically to half
    // the leftover height.
    private fun clampBubbleY(y: Int): Int {
        val half = ((bubbleDisplayHeight - bubbleSize) / 2).coerceAtLeast(0)
        return y.coerceIn(-half, half)
    }

    private fun onMicTouch(view: View, event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                draggingBubble = false
                touchDownRawX = event.rawX
                touchDownRawY = event.rawY
                bubbleParams?.let {
                    dragStartX = it.x
                    dragStartY = it.y
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val movedX = event.rawX - touchDownRawX
                val movedY = event.rawY - touchDownRawY
                if (!draggingBubble) {
                    val slop = ViewConfiguration.get(this).scaledTouchSlop
                    if (movedX * movedX + movedY * movedY >
                        (slop * slop).toFloat()
                    ) {
                        draggingBubble = true
                    }
                }
                if (draggingBubble) {
                    val params = bubbleParams ?: return true
                    // Gravity is END, so the x inset shrinks as the
                    // finger moves toward the right edge. Clamp both axes
                    // so the bubble can never be dragged off-screen (and
                    // then persisted stuck there).
                    params.x = clampBubbleX(dragStartX - movedX.toInt())
                    params.y = clampBubbleY(dragStartY + movedY.toInt())
                    bubble?.let {
                        bubbleWindowManager?.updateViewLayout(it, params)
                    }
                }
            }
            MotionEvent.ACTION_UP -> {
                if (draggingBubble) {
                    draggingBubble = false
                    bubbleParams?.let {
                        getSharedPreferences("typemate_bubble", MODE_PRIVATE)
                            .edit()
                            .putInt("x-$bubbleDisplayId", it.x)
                            .putInt("y-$bubbleDisplayId", it.y)
                            .apply()
                    }
                } else if (dictating) {
                    endDictation()
                } else if (!transcribing) {
                    beginDictation()
                }
            }
            MotionEvent.ACTION_CANCEL -> draggingBubble = false
        }
        return true
    }

    /// The desktop-parity global shortcut: hold Ctrl+Meta (the Windows
    /// key) on a physical keyboard - DeX and Android desktop mode - to
    /// dictate into the focused field, exactly like the desktop app. The
    /// keys are observed, never consumed, so every other shortcut keeps
    /// working.
    override fun onKeyEvent(event: KeyEvent): Boolean {
        when (event.keyCode) {
            KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_CTRL_RIGHT ->
                ctrlHeld = event.action == KeyEvent.ACTION_DOWN
            KeyEvent.KEYCODE_META_LEFT, KeyEvent.KEYCODE_META_RIGHT ->
                metaHeld = event.action == KeyEvent.ACTION_DOWN
            else -> return false
        }
        if (ctrlHeld && metaHeld) {
            beginDictation()
        } else if (dictating) {
            endDictation()
        }
        return false
    }

    private fun beginDictation() {
        if (dictating || transcribing) {
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            toast("Open TypeMate once to allow the microphone")
            return
        }
        dictating = true
        renderBubbleState()
        // Felt confirmation that listening started; dictation is used
        // eyes-elsewhere (the user is looking at the field, not the mic).
        vibrate(strong = true)
        channel?.invokeMethod(
            "startDictation",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {}

                override fun error(
                    code: String,
                    message: String?,
                    details: Any?,
                ) {
                    dictating = false
                    renderBubbleState()
                    toast(message ?: "Could not start recording")
                }

                override fun notImplemented() {}
            },
        )
    }

    private fun endDictation() {
        if (!dictating) {
            return
        }
        dictating = false
        transcribing = true
        renderBubbleState()
        vibrate(strong = false)
        // Watchdog: if the channel never answers (a dead engine isolate),
        // clear the transcribing state so the bubble does not wedge.
        val watchdog = Runnable {
            if (transcribing) {
                transcribing = false
                renderBubbleState()
                toast("Could not transcribe")
                updateBubbleVisibility()
            }
        }
        mainHandler.postDelayed(watchdog, TRANSCRIBE_WATCHDOG_MS)
        channel?.invokeMethod(
            "stopDictation",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    mainHandler.removeCallbacks(watchdog)
                    if (!transcribing) return
                    transcribing = false
                    renderBubbleState()
                    val transcript = result as? String ?: ""
                    // Silence is not an error: just return to idle quietly.
                    // Real failures come through the error callback below.
                    if (transcript.isNotEmpty()) {
                        insertTranscript(transcript)
                    }
                    updateBubbleVisibility()
                }

                override fun error(
                    code: String,
                    message: String?,
                    details: Any?,
                ) {
                    mainHandler.removeCallbacks(watchdog)
                    if (!transcribing) return
                    transcribing = false
                    renderBubbleState()
                    toast(message ?: "Could not transcribe")
                    updateBubbleVisibility()
                }

                override fun notImplemented() {
                    mainHandler.removeCallbacks(watchdog)
                }
            },
        )
    }

    /// Appends the transcript to the focused field. SET_TEXT replaces the
    /// whole content, so the existing text is read and re-written with the
    /// transcript joined on; fields that refuse SET_TEXT get a clipboard
    /// paste instead.
    private fun insertTranscript(transcript: String) {
        val node = focusedEditableNode()
        if (node == null) {
            toast("Tap a text field first")
            return
        }
        node.refresh()
        val current =
            if (node.isShowingHintText) "" else node.text?.toString().orEmpty()
        val merged = when {
            current.isEmpty() -> transcript
            current.endsWith(" ") || current.endsWith("\n") ->
                current + transcript
            else -> "$current $transcript"
        }
        val arguments = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                merged,
            )
        }
        val set = node.performAction(
            AccessibilityNodeInfo.ACTION_SET_TEXT,
            arguments,
        )
        if (!set) {
            val clipboard =
                getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(
                ClipData.newPlainText("TypeMate", transcript),
            )
            node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        }
    }

    private var errorPill: View? = null
    private var errorPillWindowManager: WindowManager? = null
    private val hideErrorPillRunnable = Runnable { removeErrorPill() }

    /// Failure feedback as an accessibility-overlay pill (the same red
    /// toast the desktop shows at its overlay position). A plain Toast is
    /// silently dropped for background accessibility services on newer
    /// Android — the user sees nothing — so the service draws its own.
    private fun toast(message: String) {
        removeErrorPill()
        val overlayContext = overlayContextFor(
            if (bubbleShown) bubbleDisplayId else Display.DEFAULT_DISPLAY,
        )
        val density = overlayContext.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        val pill = TextView(overlayContext).apply {
            text = message
            textSize = 13f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setTextColor(OVERLAY_TEXT)
            // Centered like every other platform's overlay text.
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            maxLines = 2
            maxWidth = dp(320)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(24).toFloat()
                setColor(ERROR_PILL)
            }
            setPadding(dp(20), dp(12), dp(20), dp(12))
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(96)
        }
        val windowManager =
            overlayContext.getSystemService(WINDOW_SERVICE) as WindowManager
        try {
            windowManager.addView(pill, params)
        } catch (_: Exception) {
            // Last resort: the classic toast, in case the overlay window
            // is rejected (should not happen for an accessibility service).
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            return
        }
        errorPill = pill
        errorPillWindowManager = windowManager
        mainHandler.postDelayed(hideErrorPillRunnable, ERROR_PILL_MS)
    }

    private fun removeErrorPill() {
        mainHandler.removeCallbacks(hideErrorPillRunnable)
        val pill = errorPill ?: return
        errorPill = null
        try {
            errorPillWindowManager?.removeView(pill)
        } catch (_: IllegalArgumentException) {
            // Already detached (service torn down while hiding).
        }
        errorPillWindowManager = null
    }

    /// Start-of-listening gets the firmer click, stop a light tick.
    /// Always on the handset's vibrator: in DeX the hand is on the phone
    /// or a mouse, and the monitor cannot vibrate anyway.
    private fun vibrate(strong: Boolean) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                    .defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                vibrator.vibrate(
                    VibrationEffect.createPredefined(
                        if (strong) {
                            VibrationEffect.EFFECT_CLICK
                        } else {
                            VibrationEffect.EFFECT_TICK
                        },
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(if (strong) 30L else 15L)
            }
        } catch (_: Exception) {
            // Haptics are a garnish; never let them break dictation.
        }
    }
}
