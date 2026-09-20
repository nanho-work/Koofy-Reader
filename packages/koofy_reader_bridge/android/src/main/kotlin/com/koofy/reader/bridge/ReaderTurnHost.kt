package com.koofy.reader.bridge

import android.content.Context
import android.os.SystemClock
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.widget.FrameLayout
import kotlin.math.abs

/** Own horizontal streams before the Readium WebView starts its native pager. */
internal class ReaderTurnHost(context: Context) : FrameLayout(context) {
    var pageMode = true
    var selecting = false
    var blocked = false
    var begin: (Boolean, Float) -> Unit = { _, _ -> }
    var move: (Float, Float) -> Unit = { _, _ -> }
    var end: (Boolean) -> Unit = {}
    private var downX = 0f
    private var downY = 0f
    private var downTime = 0L
    private var dragging = false
    private var left = true
    private var edgeStart = false
    private var ownsCorner = false
    private var velocity: VelocityTracker? = null
    private val slop = ViewConfiguration.get(context).scaledTouchSlop

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (blocked) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                downTime = event.eventTime
                edgeStart = downX < width * .18f || downX > width * .82f
                val cornerWidth = maxOf(32 * resources.displayMetrics.density, width * .08f)
                ownsCorner = pageMode && !selecting &&
                    (downX <= cornerWidth || downX >= width - cornerWidth) &&
                    (downY <= height * .25f || downY >= height * .75f)
                dragging = false
                velocity?.recycle()
                velocity = VelocityTracker.obtain().also { it.addMovement(event) }
                // Own the actual paper corner from DOWN. Otherwise WebView starts
                // a text-selection ActionMode during a stationary hold on blank paper.
                if (ownsCorner) return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - downX
                val dy = event.y - downY
                // A long press belongs to text selection; multiple fingers to the system.
                if (pageMode && !selecting && event.pointerCount == 1 &&
                    (edgeStart || event.eventTime - downTime < ViewConfiguration.getLongPressTimeout()) &&
                    abs(dx) > slop && abs(dx) > abs(dy) * 1.15f) {
                    dragging = true
                    left = dx < 0
                    parent?.requestDisallowInterceptTouchEvent(true)
                    begin(left, downY / height.coerceAtLeast(1))
                    return true
                }
            }
        }
        return false
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (blocked && !dragging) return true
        if (!dragging && ownsCorner) {
            if (event.actionMasked == MotionEvent.ACTION_MOVE &&
                abs(event.x - downX) > slop && abs(event.x - downX) > abs(event.y - downY)) {
                dragging = true
                left = event.x < downX
                begin(left, downY / height.coerceAtLeast(1))
            } else if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                ownsCorner = false
                if (event.actionMasked == MotionEvent.ACTION_UP &&
                    event.eventTime - downTime < ViewConfiguration.getLongPressTimeout()) {
                    begin(downX > width / 2, downY / height.coerceAtLeast(1))
                    end(true)
                }
                return true
            } else return true
        }
        if (!dragging) return super.onTouchEvent(event)
        velocity?.addMovement(event)
        val distance = (event.x - downX) * if (left) -1 else 1
        val travel = width.coerceAtLeast(1).toFloat()
        when (event.actionMasked) {
            MotionEvent.ACTION_POINTER_DOWN -> { dragging = false; end(false) }
            MotionEvent.ACTION_MOVE -> move((distance / travel).coerceIn(0f, 1f), event.y / height.coerceAtLeast(1))
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                move((distance / travel).coerceIn(0f, 1f), event.y / height.coerceAtLeast(1))
                velocity?.computeCurrentVelocity(1000)
                val speed = (velocity?.xVelocity ?: 0f) * if (left) -1 else 1
                val commit = event.actionMasked == MotionEvent.ACTION_UP &&
                    ReaderTurnGesture.shouldComplete(distance / travel, speed / resources.displayMetrics.density, distance > slop * 2)
                dragging = false
                ownsCorner = false
                velocity?.recycle()
                velocity = null
                end(commit)
            }
        }
        return true
    }

    fun cancelGesture() { dragging = false; ownsCorner = false; velocity?.recycle(); velocity = null }

    override fun requestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
        // Readium's WebView claims its gutter on a sub-slop MOVE. Retain the right
        // to recognize a horizontal page gesture, while leaving selection/scroll alone.
        val ownsCandidate = pageMode && !selecting &&
            (edgeStart || SystemClock.uptimeMillis() - downTime < ViewConfiguration.getLongPressTimeout())
        super.requestDisallowInterceptTouchEvent(if (ownsCandidate) false else disallowIntercept)
    }
}
