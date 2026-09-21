import IronSource
import UIKit
import AppTrackingTransparency

/// Loading keeps a stable height; reward visibility asks the host to reflow.
final class ReaderBannerFooter: UIView {
    private weak var controller: UIViewController?
    private let unitId: String?
    private var hiddenUntil: Int64?
    private let message = UILabel()
    private var banner: LPMBannerAdView?
    private var listener: ReaderBannerListener?
    private var loaded = false
    private var active = false
    private var disposed = false
    private var retryAt = Date.distantPast
    private var timer: Timer?
    private var previousWidth: CGFloat = 0
    private var trackingStatus = ATTrackingManager.trackingAuthorizationStatus
    var onHeightChanged: ((CGFloat) -> Void)?
    var desiredHeight: CGFloat {
        configured && Double(hiddenUntil ?? 0) / 1000 <= Date().timeIntervalSince1970 ? 66 : 0
    }
    private var expanded = false
    var configured: Bool { !(unitId?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }

    init(controller: UIViewController, unitId: String?, hiddenUntil: Int64?) {
        self.controller = controller
        self.unitId = unitId
        self.hiddenUntil = hiddenUntil
        super.init(frame: .zero)
        message.font = .systemFont(ofSize: 12)
        message.textAlignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false
        addSubview(message)
        NSLayoutConstraint.activate([
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            message.bottomAnchor.constraint(equalTo: bottomAnchor),
            message.heightAnchor.constraint(equalToConstant: 50),
        ])
        expanded = desiredHeight > 0
        isHidden = !expanded
    }
    required init?(coder: NSCoder) { fatalError("Use init(controller:unitId:hiddenUntil:)") }
    deinit { timer?.invalidate() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != previousWidth {
            previousWidth = bounds.width
            refresh()
        }
    }
    func applyPalette(_ palette: ReaderPalette) {
        backgroundColor = palette.background
        message.textColor = palette.secondary
    }
    func updateHiddenUntil(_ epochMs: Int64?) { hiddenUntil = epochMs; refresh() }
    func resume() {
        guard !disposed else { return }
        // The native reader can be in front while the user changes iOS settings.
        // Apply denial and discard the previous ad before resuming its requests.
        let currentTracking = ATTrackingManager.trackingAuthorizationStatus
        if configured && currentTracking != trackingStatus {
            removeBanner()
            retryAt = .distantPast
            if currentTracking != .authorized {
                LPMPrivacySettings.setGDPRConsents(["UnityAds": false, "IronSource": false])
                LPMPrivacySettings.setCCPA(true)
            }
        }
        trackingStatus = currentTracking
        active = true
        banner?.resumeAutoRefresh()
        refresh()
    }
    func pause() {
        active = false
        banner?.pauseAutoRefresh()
        timer?.invalidate()
        timer = nil
        banner?.isHidden = true
    }
    func dispose() {
        disposed = true
        pause()
        removeBanner()
    }
    private func removeBanner() {
        listener = nil
        banner?.destroy()
        banner?.removeFromSuperview()
        banner = nil
        loaded = false
    }
    private func schedule(_ seconds: TimeInterval = 60) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(0.01, min(seconds, 60)), repeats: false) { [weak self] _ in self?.refresh() }
    }
    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        expanded = value
        onHeightChanged?(value ? 66 : 0)
        isHidden = !value
    }
    private func refresh() {
        timer?.invalidate()
        guard active, !disposed, configured else { return }
        let remaining = Double(hiddenUntil ?? 0) / 1000 - Date().timeIntervalSince1970
        if remaining > 0 {
            removeBanner()
            setExpanded(false)
            schedule(remaining)
            return
        }
        setExpanded(true)
        if bounds.width < 320 {
            removeBanner()
            message.isHidden = false
            message.text = "광고 표시 공간이 부족합니다."
        } else if banner == nil, Date() >= retryAt {
            load()
        } else if loaded {
            banner?.isHidden = false
            message.isHidden = true
        } else {
            message.isHidden = false
            message.text = Date() < retryAt ? "광고를 불러오지 못했습니다." : "광고 불러오는 중…"
        }
        schedule()
    }
    private func load() {
        let config = LPMBannerAdViewConfigBuilder().set(adSize: LPMAdSize.banner()).build()
        let ad = LPMBannerAdView(adUnitId: unitId!, config: config)
        banner = ad
        loaded = false
        let callbacks = ReaderBannerListener()
        callbacks.loaded = { [weak self, weak ad] in
            guard let self, let ad, !self.disposed, self.banner === ad else { return }
            self.loaded = true
            ad.isHidden = !self.active
            self.message.isHidden = true
        }
        callbacks.failed = { [weak self, weak ad] in
            guard let self, let ad, !self.disposed, self.banner === ad else { return }
            self.removeBanner()
            self.retryAt = Date().addingTimeInterval(60)
            self.message.isHidden = false
            self.message.text = "광고를 불러오지 못했습니다."
        }
        listener = callbacks
        ad.setDelegate(callbacks)
        ad.translatesAutoresizingMaskIntoConstraints = false
        ad.isHidden = true
        addSubview(ad)
        NSLayoutConstraint.activate([
            ad.widthAnchor.constraint(equalToConstant: 320),
            ad.heightAnchor.constraint(equalToConstant: 50),
            ad.centerXAnchor.constraint(equalTo: centerXAnchor),
            ad.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        message.isHidden = false
        message.text = "광고 불러오는 중…"
        if let controller { ad.loadAd(with: controller) }
    }
}

private final class ReaderBannerListener: NSObject, LPMBannerAdViewDelegate {
    var loaded: (() -> Void)?
    var failed: (() -> Void)?
    func didLoadAd(with adInfo: LPMAdInfo) { loaded?() }
    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) { failed?() }
    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) { failed?() }
}
