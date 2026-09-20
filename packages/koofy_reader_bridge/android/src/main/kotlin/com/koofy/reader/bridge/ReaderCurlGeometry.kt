package com.koofy.reader.bridge

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** Geometry is independent of frame timing; the grabbed edge's X follows touch 1:1. */
internal object ReaderCurlGeometry {
    data class Fold(val normalX: Float, val normalY: Float, val radius: Float, val fold: Float)

    fun fold(leafWidth: Float, height: Float, viewportWidth: Float, progress: Float,
             grabY: Float, fingerY: Float): Fold {
        val travel = (viewportWidth * progress).coerceIn(0f, 2 * leafWidth)
        val phase = travel / (2 * leafWidth)
        // A corner lifts diagonally; a middle grab stays vertical unless dragged
        // vertically. Keep the DOWN anchor fixed rather than moving it every frame.
        val lift = sin(PI * phase).toFloat()
        val tilt = ((grabY - .5f) * 1.1f + (grabY - fingerY) * height / leafWidth)
            .coerceIn(-.65f, .65f) * lift
        val nx = cos(tilt)
        val ny = sin(tilt)
        val normalTravel = travel / nx
        val radius = minOf(leafWidth * .065f, normalTravel / (PI.toFloat() * 1.1f)).coerceAtLeast(.001f)
        // Solve the folded free edge, not a guessed percentage of the fold line.
        val crease = leafWidth * nx - (normalTravel + PI.toFloat() * radius) / 2
        return Fold(nx, ny, radius, crease)
    }
}
