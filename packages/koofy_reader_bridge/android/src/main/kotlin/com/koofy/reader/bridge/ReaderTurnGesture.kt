package com.koofy.reader.bridge

/** Progress uses viewport travel for both single pages and spreads. */
internal object ReaderTurnGesture {
    fun shouldComplete(progress: Float, velocityDp: Float, moved: Boolean): Boolean =
        progress >= .5f || (moved && progress > 0f && velocityDp > 650f)
}
