package com.koofy.reader.bridge

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class ReaderTurnGeometryTest {
    @Test fun releaseThresholdAndFlingAreIndependentOfColumnCount() {
        assertFalse(ReaderTurnGesture.shouldComplete(.49f, 0f, true))
        assertTrue(ReaderTurnGesture.shouldComplete(.5f, 0f, true))
        assertTrue(ReaderTurnGesture.shouldComplete(.7f, -200f, true))
        assertTrue(ReaderTurnGesture.shouldComplete(.15f, 900f, true))
        assertFalse(ReaderTurnGesture.shouldComplete(.15f, -900f, true))
        assertFalse(ReaderTurnGesture.shouldComplete(0f, 900f, true))
        assertFalse(ReaderTurnGesture.shouldComplete(.01f, 900f, false))
    }

    @Test fun grabbedEdgeTracksFingerAcrossSingleSpreadAndCornerHeights() {
        for (leaf in listOf(500f, 1000f)) for (grab in listOf(.05f, .5f, .95f)) {
            for (p in listOf(.05f, .25f, .5f, .8f)) {
                val f = ReaderCurlGeometry.fold(leaf, 1400f, 1000f, p, grab, grab)
                val distance = leaf * f.normalX
                val angle = ((distance - f.fold) / f.radius).coerceIn(0f, PI.toFloat())
                val bent = if (distance < f.fold + PI * f.radius) f.fold + f.radius * sin(angle)
                    else 2 * f.fold + PI.toFloat() * f.radius - distance
                val x = leaf + (bent - distance) * f.normalX
                assertEquals("Grabbed edge must follow finger, leaf=$leaf p=$p", leaf - 1000f * p, x, .05f)
                assertTrue(x.isFinite())
            }
        }
    }

    @Test fun upperAndLowerCornersMirrorWhileMiddleStaysStraight() {
        val top = ReaderCurlGeometry.fold(500f, 1400f, 1000f, .3f, .05f, .05f)
        val bottom = ReaderCurlGeometry.fold(500f, 1400f, 1000f, .3f, .95f, .95f)
        val middle = ReaderCurlGeometry.fold(500f, 1400f, 1000f, .3f, .5f, .5f)
        assertTrue(top.normalY < 0)
        assertTrue(bottom.normalY > 0)
        assertEquals(-top.normalY, bottom.normalY, .0001f)
        assertEquals(0f, middle.normalY, .0001f)
        val end = ReaderCurlGeometry.fold(500f, 1400f, 1000f, 1f, .95f, .6f)
        assertEquals(0f, end.normalY, .0001f)
    }
}
