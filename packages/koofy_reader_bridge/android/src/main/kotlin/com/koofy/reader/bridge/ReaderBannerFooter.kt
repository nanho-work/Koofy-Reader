package com.koofy.reader.bridge

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.unity3d.mediation.LevelPlayAdInfo
import com.unity3d.mediation.LevelPlayAdError
import com.unity3d.mediation.LevelPlayAdSize
import com.unity3d.mediation.banner.LevelPlayBannerAdView
import com.unity3d.mediation.banner.LevelPlayBannerAdViewListener

/** A stable 50dp banner plus a 16dp gap from page controls. Never overlays text. */
internal class ReaderBannerFooter(
    private val host: Activity,
    private val unitId: String?,
    private var hiddenUntil: Long?,
    private val onAdInteraction: () -> Unit = {},
    private val beforeResize: () -> Unit = {}
) : FrameLayout(host) {
    private val handler = Handler(Looper.getMainLooper())
    private val message = TextView(host).apply {
        gravity = Gravity.CENTER
        textSize = 12f
        setPadding(dp(12), 0, dp(12), 0)
    }
    private var banner: LevelPlayBannerAdView? = null
    private var loaded = false
    private var active = false
    private var disposed = false
    private var retryAt = 0L
    private val refreshTask = Runnable { refresh() }
    val configured: Boolean get() = !unitId.isNullOrBlank()

    init {
        setPadding(0, dp(16), 0, 0)
        addView(message, LayoutParams(-1, dp(50), Gravity.BOTTOM))
        visibility = if (configured && (hiddenUntil ?: 0L) <= System.currentTimeMillis()) View.VISIBLE else View.GONE
        addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            if (right - left != oldRight - oldLeft) refresh()
        }
    }

    fun applyPalette(palette: ReaderPalette) {
        setBackgroundColor(palette.background)
        message.setTextColor(palette.secondary)
    }

    fun updateHiddenUntil(epochMs: Long?) { hiddenUntil = epochMs; refresh() }

    fun resume() {
        if (disposed) return
        active = true
        banner?.resumeAutoRefresh()
        refresh()
    }

    fun pause() {
        active = false
        handler.removeCallbacks(refreshTask)
        banner?.pauseAutoRefresh()
    }

    fun dispose() {
        disposed = true
        pause()
        removeBanner()
    }

    private fun removeBanner() {
        val old = banner
        banner = null
        loaded = false
        if (old != null) { removeView(old); old.destroy() }
    }

    private fun setExpanded(expanded: Boolean) {
        val next = if (expanded) View.VISIBLE else View.GONE
        if (visibility == next) return
        beforeResize()
        visibility = next
    }

    private fun refresh() {
        handler.removeCallbacks(refreshTask)
        if (disposed || !active || !configured) return
        val now = System.currentTimeMillis()
        val remaining = (hiddenUntil ?: 0L) - now
        if (remaining > 0) {
            removeBanner()
            setExpanded(false)
            handler.postDelayed(refreshTask, remaining.coerceIn(1L, 60_000L))
            return
        }
        setExpanded(true)
        if (width < dp(320)) {
            removeBanner()
            message.visibility = View.VISIBLE
            message.text = "광고 표시 공간이 부족합니다."
        } else if (banner == null && now >= retryAt) {
            load()
        } else if (!loaded) {
            message.visibility = View.VISIBLE
            message.text = if (retryAt > now) "광고를 불러오지 못했습니다." else "광고 불러오는 중…"
        }
        handler.postDelayed(refreshTask, 60_000L)
    }

    private fun load() {
        val config = LevelPlayBannerAdView.Config.Builder().setAdSize(LevelPlayAdSize.BANNER).build()
        val ad = LevelPlayBannerAdView(host, unitId!!, config)
        banner = ad
        loaded = false
        message.text = "광고 불러오는 중…"
        message.visibility = View.VISIBLE
        ad.visibility = View.INVISIBLE
        ad.setBannerListener(object : LevelPlayBannerAdViewListener {
            override fun onAdLoaded(adInfo: LevelPlayAdInfo) {
                if (disposed || banner !== ad) return
                loaded = true
                message.visibility = View.GONE
                ad.visibility = View.VISIBLE
            }
            override fun onAdLoadFailed(error: LevelPlayAdError) {
                if (disposed || banner !== ad) return
                removeBanner()
                retryAt = System.currentTimeMillis() + 60_000L
                message.text = "광고를 불러오지 못했습니다."
                message.visibility = View.VISIBLE
            }
            override fun onAdDisplayed(adInfo: LevelPlayAdInfo) {}
            override fun onAdDisplayFailed(adInfo: LevelPlayAdInfo, error: LevelPlayAdError) { onAdLoadFailed(error) }
            override fun onAdClicked(adInfo: LevelPlayAdInfo) { onAdInteraction() }
            override fun onAdExpanded(adInfo: LevelPlayAdInfo) { onAdInteraction() }
            override fun onAdCollapsed(adInfo: LevelPlayAdInfo) {}
            override fun onAdLeftApplication(adInfo: LevelPlayAdInfo) { onAdInteraction() }
        })
        addView(ad, LayoutParams(dp(320), dp(50), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))
        ad.loadAd()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
