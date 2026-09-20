@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package com.koofy.reader.bridge

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.provider.Settings
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.shared.publication.Locator

/** Single owner of page gestures, native navigation, and transient rendering resources. */
internal class ReaderPageTurns(
    private val activity: AppCompatActivity,
    private val host: ReaderTurnHost,
    private val overlay: ReaderPageCurlView,
    private val provider: ReaderPageSurfaces,
    private val navigator: () -> EpubNavigatorFragment?,
    private val preferences: () -> EpubPreferences,
    private val curlEnabled: () -> Boolean,
    private val available: () -> Boolean,
    private val commit: (Locator) -> Boolean,
) {
    var generation = 0L
        private set
    var surfaces: PageSurfaces? = null
        private set
    var state = "idle"
        private set
    var fallbackCount = 0
        private set
    val preparationFailure: String? get() = provider.lastFailure
    val captureMillis: Long get() = provider.lastCaptureMillis
    val capturedBytes: Long get() = provider.capturedBytes
    val showingCurl: Boolean get() = overlay.visibility == android.view.View.VISIBLE
    private var prepareJob: Job? = null
    private var commitTimeout: Job? = null
    private var animator: ValueAnimator? = null
    private var forward = true
    private var activeTarget: PageSurface? = null
    private var active = true
    private var leftward = true
    private var grabY = .5f
    private var fingerY = .5f
    private var dragProgress = 0f
    private var waitTimeout: Job? = null
    private var queuedRequest: Boolean? = null
    private val wantsCurl: Boolean get() = curlEnabled() && !reducedMotion()

    init {
        host.begin = { left, y -> begin(left, y) }
        host.move = { progress, y ->
            if (state == "dragging") {
                dragProgress = progress
                fingerY = y
                if (activeTarget != null) overlay.drag(progress, y)
            }
        }
        host.end = { complete -> finish(complete) }
    }

    fun mainSettled() {
        if (state == "committing") {
            commitTimeout?.cancel()
            overlay.clear()
            val target = activeTarget
            activeTarget = null
            state = "idle"
            host.blocked = false
            if (target != null && surfaces?.advance(target) == true) {
                prepareWindow()
                drainRequest()
                return
            }
        }
        if (state == "idle" && active) refresh()
    }

    fun refresh() {
        invalidate()
        if (!active || !wantsCurl) return
        prepareWindow()
    }

    private fun prepareWindow() {
        val reader = navigator() ?: return
        prepareJob?.cancel()
        val epoch = generation
        prepareJob = activity.lifecycleScope.launch {
            provider.prepare(reader, preferences(), epoch, surfaces, forward) { result ->
                if (generation == epoch) {
                    surfaces = result
                    activatePreparedTurn()
                } else result.recycle()
            }
            if (epoch == generation && provider.sourceMismatch) {
                refresh()
                return@launch
            }
            if (epoch == generation && state == "waiting") {
                // Boundary or failed preparation must not trap input. A temporary
                // cache miss never silently changes a curl into an instant turn.
                cancelWaiting()
            }
        }
    }

    private fun activatePreparedTurn() {
        if (activeTarget != null || !wantsCurl || state !in listOf("dragging", "waiting")) return
        val frames = surfaces ?: return
        val target = if (forward) frames.next else frames.previous
        if (target == null) return
        try {
            overlay.show(frames, target, leftward, grabY)
            overlay.drag(dragProgress, fingerY)
            activeTarget = target
            if (state == "waiting") {
                waitTimeout?.cancel()
                state = "dragging"
                finish(true)
            }
        } catch (_: OutOfMemoryError) {
            overlay.clear()
            activeTarget = null
            cancelWaiting()
        }
    }

    private fun cancelWaiting() {
        waitTimeout?.cancel()
        if (state == "waiting") {
            queuedRequest = null
            state = "idle"
            host.blocked = false
        }
    }

    private fun drainRequest() {
        val next = queuedRequest ?: return
        val epoch = generation
        queuedRequest = null
        host.post { if (generation == epoch && active) request(next) }
    }

    fun invalidate() {
        generation++
        waitTimeout?.cancel()
        queuedRequest = null
        prepareJob?.cancel()
        prepareJob = null
        provider.disposeNavigator()
        animator?.removeAllListeners()
        animator?.cancel()
        animator = null
        commitTimeout?.cancel()
        overlay.clear()
        surfaces?.recycle()
        surfaces = null
        activeTarget = null
        state = "idle"
        host.blocked = false
        host.cancelGesture()
    }

    private fun reducedMotion(): Boolean = Settings.Global.getFloat(activity.contentResolver,
        Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

    fun request(next: Boolean) {
        if (state != "idle") { queuedRequest = next; return }
        if (!available()) return
        val rtl = navigator()?.settings?.value?.readingProgression == ReadingProgression.RTL
        begin(if (rtl) !next else next, .82f)
        finish(true)
    }

    private fun begin(left: Boolean, y: Float) {
        if (state != "idle" || !available()) return
        val rtl = navigator()?.settings?.value?.readingProgression == ReadingProgression.RTL
        forward = if (rtl) !left else left
        leftward = left
        grabY = y
        fingerY = y
        dragProgress = 0f
        activeTarget = null
        state = "dragging"
        activatePreparedTurn()
    }

    private fun finish(complete: Boolean) {
        if (state != "dragging") return
        if (activeTarget == null) {
            if (!complete) { state = "idle"; return }
            if (wantsCurl && surfaces?.known(if (forward) 1 else -1) == true) {
                state = "idle" // A known book boundary is not a capture failure.
                return
            }
            if (wantsCurl && prepareJob?.isActive == true &&
                surfaces?.known(if (forward) 1 else -1) != true) {
                state = "waiting"
                host.blocked = true
                waitTimeout?.cancel()
                waitTimeout = activity.lifecycleScope.launch {
                    delay(5_000)
                    cancelWaiting()
                }
            } else {
                if (wantsCurl) fallbackCount++
                commitTurn()
            }
            return
        }
        state = "settling"
        host.blocked = true
        val end = if (complete) overlay.completionProgress else 0f
        animator = ValueAnimator.ofFloat(overlay.progress, end).apply {
            duration = (280 * kotlin.math.abs(end - overlay.progress) / overlay.completionProgress)
                .toLong().coerceIn(100, 280)
            interpolator = android.view.animation.DecelerateInterpolator()
            addUpdateListener { overlay.progress = it.animatedValue as Float }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    animator = null
                    if (complete) commitTurn() else {
                        overlay.clear()
                        activeTarget = null
                        state = "idle"
                        host.blocked = false
                        drainRequest()
                    }
                }
            })
            start()
        }
    }

    private fun commitTurn() {
        state = "committing"
        prepareJob?.cancel()
        host.blocked = true
        val target = activeTarget
        val reader = navigator()
        val moved = if (target != null) commit(target.locator)
            else if (forward) reader?.goForward(false) == true else reader?.goBackward(false) == true
        if (!moved) { invalidate(); return }
        commitTimeout?.cancel()
        commitTimeout = activity.lifecycleScope.launch {
            // A no-op at a book boundary may not produce a pagination event. Never trap input.
            delay(if (target == null) 1_200 else 12_000)
            if (state == "committing") { invalidate(); refresh() }
        }
    }

    fun dispose() { invalidate(); provider.disposeNavigator() }
    fun suspendPreparation() { active = false; dispose() }
    fun resumePreparation() { active = true; refresh() }
}
