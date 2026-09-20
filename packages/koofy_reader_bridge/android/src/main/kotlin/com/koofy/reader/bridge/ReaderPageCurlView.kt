package com.koofy.reader.bridge

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/** A cylindrical paper mesh, including the real target page on its reverse face. */
internal class ReaderPageCurlView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private var surfaces: PageSurfaces? = null
    private var target: PageSurface? = null
    private var front: Bitmap? = null
    private var back: Bitmap? = null
    private var toLeft = true
    private var spread = false
    private var fingerY = .8f
    private val nx = 64
    private val ny = 40
    private val vertices = FloatArray((nx + 1) * (ny + 1) * 2)
    private val frontUV = FloatArray(vertices.size)
    private val backUV = FloatArray(vertices.size)
    private val frontIndices = ShortArray(nx * ny * 6)
    private val backIndices = ShortArray(nx * ny * 6)
    private val colors = IntArray(vertices.size / 2)
    private val angles = FloatArray(colors.size)
    private val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private var frontShader: BitmapShader? = null
    private var backShader: BitmapShader? = null
    var progress: Float = 0f
        set(value) { field = value.coerceIn(0f, 1f); invalidate() }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        isClickable = false
        visibility = INVISIBLE
        // Indexed textured triangles are accelerated from Android 10. Older systems
        // render only this temporary effect layer in software, never the live text.
        if (android.os.Build.VERSION.SDK_INT < 29) setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun show(frames: PageSurfaces, destination: PageSurface, left: Boolean, y: Float) {
        clear()
        surfaces = frames
        target = destination
        toLeft = left
        spread = frames.columns == 2
        fingerY = y.coerceIn(0f, 1f)
        val source = frames.source.image
        val next = destination.image
        if (spread) {
            val half = source.width / 2
            front = Bitmap.createBitmap(source, if (left) half else 0, 0, half, source.height)
            back = Bitmap.createBitmap(next, if (left) 0 else half, 0, half, next.height)
        } else {
            front = source
            back = next
        }
        frontShader = BitmapShader(requireNotNull(front), Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        backShader = BitmapShader(requireNotNull(back), Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        progress = 0f
        visibility = VISIBLE
    }

    fun drag(value: Float, y: Float) {
        fingerY = y.coerceIn(0f, 1f)
        progress = value
    }

    fun clear() {
        if (spread) { front?.recycle(); back?.recycle() }
        front = null
        back = null
        surfaces = null
        target = null
        frontShader = null
        backShader = null
        visibility = INVISIBLE
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val frames = surfaces ?: return
        val destination = target ?: return
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        if (progress <= .001f) {
            canvas.drawBitmap(frames.source.image, null, rect, paint)
            return
        }
        if (progress >= .999f) {
            canvas.drawBitmap(destination.image, null, rect, paint)
            return
        }
        canvas.drawBitmap(destination.image, null, rect, paint)
        val leafWidth = if (spread) width / 2f else width.toFloat()
        if (spread) {
            val half = frames.source.image.width / 2
            canvas.drawBitmap(frames.source.image,
                Rect(if (toLeft) 0 else half, 0, if (toLeft) half else half * 2, frames.source.image.height),
                RectF(if (toLeft) 0f else leafWidth, 0f, if (toLeft) leafWidth else width.toFloat(), height.toFloat()), paint)
        }
        canvas.save()
        if (!toLeft) { canvas.translate(width.toFloat(), 0f); canvas.scale(-1f, 1f) }
        if (spread) canvas.translate(leafWidth, 0f)
        drawPaper(canvas, leafWidth, height.toFloat())
        canvas.restore()
    }

    private fun drawPaper(canvas: Canvas, w: Float, h: Float) {
        val frontImage = front ?: return
        val backImage = back ?: return
        // Finger height tilts the bend near the grabbed corner. The tilt vanishes
        // at both endpoints so the final mesh exactly matches the flat EPUB page.
        val tilt = (fingerY - .5f) * .6f * sin(PI * progress).toFloat()
        val normalX = cos(tilt)
        val normalY = sin(tilt)
        val radius = w * (.025f + .105f * sin(PI * progress).toFloat())
        val fold = w * (1 - progress) - (PI * radius / 2).toFloat()
        for (y in 0..ny) for (x in 0..nx) {
            val index = y * (nx + 1) + x
            val px = x * w / nx
            val py = y * h / ny
            val distance = px * normalX + (py - h * fingerY) * normalY
            val theta = ((distance - fold) / radius).coerceIn(0f, PI.toFloat())
            val bent = when {
                distance <= fold -> distance
                distance < fold + PI * radius -> fold + radius * sin(theta)
                else -> 2 * fold + PI.toFloat() * radius - distance
            }
            val delta = bent - distance
            vertices[index * 2] = px + delta * normalX
            vertices[index * 2 + 1] = py + delta * normalY
            angles[index] = theta
            val shade = (255 - 48 * abs(sin(theta))).toInt().coerceIn(180, 255)
            colors[index] = Color.rgb(shade, shade, shade)
            val u = x.toFloat() / nx
            val v = y.toFloat() / ny
            frontUV[index * 2] = (if (toLeft) u else 1 - u) * frontImage.width
            frontUV[index * 2 + 1] = v * frontImage.height
            backUV[index * 2] = (if (toLeft) 1 - u else u) * backImage.width
            backUV[index * 2 + 1] = v * backImage.height
        }
        var frontCount = 0
        var backCount = 0
        for (y in 0 until ny) for (x in 0 until nx) {
            val i = y * (nx + 1) + x
            val a = i + 1
            val b = i + nx + 2
            val c = i + nx + 1
            val frontFacing = (angles[i] + angles[a] + angles[b] + angles[c]) / 4 < PI / 2
            val indices = if (frontFacing) frontIndices else backIndices
            var count = if (frontFacing) frontCount else backCount
            indices[count++] = i.toShort()
            indices[count++] = a.toShort()
            indices[count++] = b.toShort()
            indices[count++] = i.toShort()
            indices[count++] = b.toShort()
            indices[count++] = c.toShort()
            if (frontFacing) frontCount = count else backCount = count
        }
        // The bend's contact shadow is a continuous line. Drawing each mesh cell's
        // border would introduce repeated bands that do not exist on a paper surface.
        shadow.color = Color.argb((34 * sin(PI * progress)).toInt(), 0, 0, 0)
        shadow.strokeWidth = w * .045f
        val top = (fold + radius + h * fingerY * normalY) / normalX
        val bottom = (fold + radius - h * (1 - fingerY) * normalY) / normalX
        canvas.drawLine(top + w * .02f, 0f, bottom + w * .02f, h, shadow)
        paint.shader = frontShader
        if (frontCount > 0) canvas.drawVertices(Canvas.VertexMode.TRIANGLES, vertices.size,
            vertices, 0, frontUV, 0, colors, 0, frontIndices, 0, frontCount, paint)
        paint.shader = backShader
        if (backCount > 0) canvas.drawVertices(Canvas.VertexMode.TRIANGLES, vertices.size,
            vertices, 0, backUV, 0, colors, 0, backIndices, 0, backCount, paint)
        paint.shader = null
    }
}
