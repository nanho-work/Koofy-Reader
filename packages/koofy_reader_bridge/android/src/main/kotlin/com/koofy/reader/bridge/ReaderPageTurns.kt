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

    init {
        host.begin = { left, y -> begin(left, y) }
        host.move = { progress, y -> if (state == "dragging") overlay.drag(progress, y) }
        host.end = { complete -> finish(complete) }
    }

    fun mainSettled() {
        if (state == "committing") {
            commitTimeout?.cancel()
            overlay.clear()
            state = "idle"
            host.blocked = false
        }
        if (state == "idle" && active) refresh()
    }

    fun refresh() {
        invalidate()
        if (!active || !curlEnabled()) { provider.disposeNavigator(); return }
        val reader = navigator() ?: return
        val epoch = generation
        prepareJob = activity.lifecycleScope.launch {
            provider.prepare(reader, preferences(), epoch) { result ->
                if (generation == epoch) surfaces = result else result.recycle()
            }
        }
    }

    fun invalidate() {
        generation++
        prepareJob?.cancel()
        prepareJob = null
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
        if (state != "idle" || !available()) return
        val rtl = navigator()?.settings?.value?.readingProgression == ReadingProgression.RTL
        begin(if (rtl) !next else next, .82f)
        finish(true)
    }

    private fun begin(left: Boolean, y: Float) {
        if (state != "idle" || !available()) return
        val rtl = navigator()?.settings?.value?.readingProgression == ReadingProgression.RTL
        forward = if (rtl) !left else left
        val frames = surfaces
        val target = if (forward) frames?.next else frames?.previous
        activeTarget = if (curlEnabled() && !reducedMotion()) target else null
        // The free edge travels two leaf widths during a physical turn. A single
        // visible page therefore follows a finger at half the spread's progress rate.
        host.travelFactor = if (activeTarget != null && frames?.columns == 1) 2f else 1f
        state = "dragging"
        if (frames != null && activeTarget != null) {
            try { overlay.show(frames, activeTarget!!, left, y) }
            catch (_: OutOfMemoryError) {
                overlay.clear()
                activeTarget = null
                prepareJob?.cancel()
                surfaces?.recycle()
                surfaces = null
                provider.disposeNavigator()
                fallbackCount++
            }
        }
        else if (curlEnabled()) fallbackCount++
    }

    private fun finish(complete: Boolean) {
        if (state != "dragging") return
        if (activeTarget == null) {
            if (complete) commitTurn() else state = "idle"
            return
        }
        state = "settling"
        host.blocked = true
        val end = if (complete) 1f else 0f
        animator = ValueAnimator.ofFloat(overlay.progress, end).apply {
            duration = (340 * kotlin.math.abs(end - overlay.progress)).toLong().coerceAtLeast(100)
            addUpdateListener { overlay.progress = it.animatedValue as Float }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    animator = null
                    if (complete) commitTurn() else {
                        overlay.clear()
                        activeTarget = null
                        state = "idle"
                        host.blocked = false
                    }
                }
            })
            start()
        }
    }

    private fun commitTurn() {
        state = "committing"
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
