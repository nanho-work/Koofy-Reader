package com.koofy.reader.bridge

import android.view.MotionEvent
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TranslationTest {
    @Test fun longHoldAtCornerDoesNotBecomePageDragInTranslationMode() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val host = ReaderTurnHost(ApplicationProvider.getApplicationContext()).apply { translationMode = true; layout(0,0,400,700) }
            var turns = 0
            host.begin = { _, _ -> turns++ }
            val now = SystemClock.uptimeMillis()
            fun event(time: Long, action: Int, x: Float) = MotionEvent.obtain(now, time, action, x, 30f, 0)
            val down = event(now, MotionEvent.ACTION_DOWN, 390f)
            assertFalse(host.onInterceptTouchEvent(down)); down.recycle()
            val slow = event(now + 1200, MotionEvent.ACTION_MOVE, 200f)
            assertFalse(host.onInterceptTouchEvent(slow)); slow.recycle()
            assertEquals(0, turns)
            val again = event(now, MotionEvent.ACTION_DOWN, 390f)
            host.onInterceptTouchEvent(again); again.recycle()
            val fast = event(now + 80, MotionEvent.ACTION_MOVE, 250f)
            assertTrue(host.onInterceptTouchEvent(fast)); fast.recycle()
            assertEquals(1, turns)
            host.cancelGesture(); host.selecting = true
            val selected = event(now + 90, MotionEvent.ACTION_MOVE, 150f)
            assertFalse(host.onInterceptTouchEvent(selected)); selected.recycle()
        }
    }
}
