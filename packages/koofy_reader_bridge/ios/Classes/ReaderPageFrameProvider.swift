import ReadiumNavigator
import ReadiumShared
import UIKit
import WebKit

/// A frame is a complete Readium viewport, not a guessed global page number.
struct ReaderPageFrame {
    let image: UIImage
    let locator: Locator
    let columns: Int
    let viewport: CGSize
    let generation: Int
    let visibleText: String
}

struct ReaderPageFrames {
    let previous: ReaderPageFrame?
    let current: ReaderPageFrame
    let next: ReaderPageFrame?
    let rightToLeft: Bool

    func frame(at offset: Int) -> ReaderPageFrame? {
        switch offset {
        case -1: return previous
        case 0: return current
        case 1: return next
        default: return nil
        }
    }
}

/// Readium keeps its WKWebViews internal. This adapter uses only public UIView /
/// WKWebView APIs, validates the actually visible viewport, and fails closed if
/// Readium changes its view hierarchy. It does not use reflection or KVC.
@MainActor
enum ReaderWebViewport {
    static func webViews(in view: UIView) -> [WKWebView] {
        if let web = view as? WKWebView { return [web] }
        return view.subviews.flatMap { webViews(in: $0) }
    }

    static func visibleWebView(in navigator: EPUBNavigatorViewController) throws -> WKWebView {
        let candidates = webViews(in: navigator.view).filter { web in
            let rect = navigator.view.convert(web.bounds, from: web)
            return !web.isHidden && web.alpha > 0 && web.scrollView.alpha > 0.95 &&
                rect.intersection(navigator.view.bounds).width > navigator.view.bounds.width * 0.9 &&
                rect.intersection(navigator.view.bounds).height > navigator.view.bounds.height * 0.5
        }
        guard candidates.count == 1, let web = candidates.first, web.window != nil else {
            throw FrameError.viewportUnavailable
        }
        return web
    }

    /// Both the chapter pager and inner WebView pager must stop moving while
    /// our input policy owns page turns. Selection and link recognizers remain.
    static func setPagingEnabled(_ enabled: Bool, in root: UIView) {
        if let scroll = root as? UIScrollView { scroll.isScrollEnabled = enabled }
        root.subviews.forEach { setPagingEnabled(enabled, in: $0) }
    }

    enum FrameError: Error { case viewportUnavailable, notReady, invalidAnchor, stale, captureFailed }

    static func anchorScript(locator: Locator?, restore: Bool) throws -> String {
        let bundle = Bundle(for: KoofyReaderViewController.self)
        guard let resource = bundle.url(forResource: "KoofyReaderAssets", withExtension: "bundle"),
              let resources = Bundle(url: resource),
              let script = resources.url(forResource: "reader_anchor", withExtension: "js") else {
            throw FrameError.invalidAnchor
        }
        return try String(contentsOf: script, encoding: .utf8)
            .replacingOccurrences(of: "__KOOFY_RESTORE__", with: restore ? "true" : "false")
            .replacingOccurrences(of: "__KOOFY_ANCHOR__", with: try locator?.jsonString() ?? "null")
    }

    static func exactLocator(in navigator: EPUBNavigatorViewController) async throws -> Locator {
        guard let fallback = await navigator.firstVisibleElementLocator() ?? navigator.currentLocation else {
            throw FrameError.invalidAnchor
        }
        // firstVisibleElementLocator carries a precise selector but omits
        // publication progress/position. Match the live DOM progression to
        // Readium's settled location before borrowing its metadata. Matching
        // only HREF would still accept the previous page of the same chapter.
        let actualProgression = try await navigator.evaluateJavaScript("Math.abs(window.scrollX) / Math.max(1, document.scrollingElement.scrollWidth)").get()
        guard let progression = (actualProgression as? NSNumber)?.doubleValue else { throw FrameError.invalidAnchor }
        var metadata: Locator?
        for _ in 0..<100 {
            try Task.checkCancellation()
            if navigator.viewport != nil, let location = navigator.currentLocation, location.href == fallback.href,
               let reported = location.locations.progression, abs(reported - progression) < 0.00001 {
                metadata = location
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let metadata else { throw FrameError.notReady }
        let value = try await navigator.evaluateJavaScript(anchorScript(locator: nil, restore: false)).get()
        guard let raw = value as? String,
              let snapshot = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              var json = try JSONSerialization.jsonObject(with: Data(metadata.jsonString().utf8)) as? [String: Any] else {
            throw FrameError.invalidAnchor
        }
        // Do not invent a restorable text locator on an illustration-only or
        // blank viewport. A body selector can identify many different pages.
        // This viewport uses the regular Readium transition instead.
        guard let locations = snapshot["locations"] as? [String: Any] else { throw FrameError.invalidAnchor }
        var merged = json["locations"] as? [String: Any] ?? [:]
        merged.removeValue(forKey: "fragments")
        merged.merge(locations) { _, new in new }
        json["locations"] = merged
        json["text"] = snapshot["text"]
        return try Locator(jsonString: String(decoding: JSONSerialization.data(withJSONObject: json), as: UTF8.self))
    }

    /// Wait for fonts/images AND an unchanged scroll/layout signature. The
    /// readiness condition, rather than a fixed sleep, controls capture.
    static func waitUntilStable(_ navigator: EPUBNavigatorViewController) async throws {
        var lastSignature: String?
        var stableCount = 0
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try Task.checkCancellation()
            let result = try? await navigator.evaluateJavaScript("""
            (() => {
              if (document.readyState !== 'complete' || (document.fonts && document.fonts.status !== 'loaded') ||
                  Array.from(document.images).some(i => !i.complete)) return null;
              const r = document.documentElement;
              return [innerWidth, innerHeight, scrollX, scrollY, r.scrollWidth, r.scrollHeight,
                      getComputedStyle(r).columnCount].join(':');
            })()
            """).get()
            if let signature = result as? String, (try? visibleWebView(in: navigator)) != nil {
                stableCount = signature == lastSignature ? stableCount + 1 : 0
                lastSignature = signature
                if stableCount >= 3 { return }
            } else { stableCount = 0 }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw FrameError.notReady
    }

    static func capture(_ navigator: EPUBNavigatorViewController, generation: Int,
                        background: UIColor) async throws -> ReaderPageFrame {
        try Task.checkCancellation()
        let web = try visibleWebView(in: navigator)
        let bounds = navigator.view.bounds
        guard bounds.width > 1, bounds.height > 1 else { throw FrameError.viewportUnavailable }
        let locator = try await exactLocator(in: navigator)
        let columns = try await navigator.evaluateJavaScript("Number.parseInt(getComputedStyle(document.documentElement).columnCount) || 1").get()
        let text = locator.text.highlight ?? ""
        let rect = navigator.view.convert(web.bounds, from: web)
        let deviceScale = navigator.view.window?.screen.scale ?? 2
        // Three cached viewports stay under ~30 MiB before temporary UIKit
        // animation surfaces. Live text always remains at the native scale.
        let scale = min(min(deviceScale, 2), sqrt(2_500_000 / (bounds.width * bounds.height)))
        let config = WKSnapshotConfiguration()
        config.rect = web.bounds
        config.snapshotWidth = NSNumber(value: Double(web.bounds.width * scale / deviceScale))
        config.afterScreenUpdates = true
        // Bridge the exactly-once WebKit callback without throwing inside it.
        let snapshotResult: Result<UIImage, Error> = await withCheckedContinuation { continuation in
            web.takeSnapshot(with: config) { image, error in
                if let image { continuation.resume(returning: .success(image)) }
                else { continuation.resume(returning: .failure(error ?? FrameError.captureFailed)) }
            }
        }
        let snapshot = try snapshotResult.get()
        try Task.checkCancellation()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            snapshot.draw(in: rect)
        }
        return ReaderPageFrame(image: image, locator: locator,
            columns: (columns as? NSNumber)?.intValue == 2 ? 2 : 1,
            viewport: bounds.size, generation: generation, visibleText: text)
    }
}

/// Owns an isolated preview navigator. It never receives the host's journal or
/// event callback, and never navigates the user's active navigator.
@MainActor
final class ReaderPageFrameProvider {
    private var preview: EPUBNavigatorViewController?

    func removePreview() {
        guard let preview else { return }
        preview.willMove(toParent: nil)
        preview.view.removeFromSuperview()
        preview.removeFromParent()
        self.preview = nil
    }

    func prepare(current: EPUBNavigatorViewController, parent: UIViewController,
                 container: UIView, generation: Int, background: UIColor,
                 factory: (Locator) throws -> EPUBNavigatorViewController) async throws -> ReaderPageFrames {
        removePreview()
        try await ReaderWebViewport.waitUntilStable(current)
        let source = try await ReaderWebViewport.capture(current, generation: generation, background: background)
        let preview = try factory(source.locator)
        self.preview = preview
        parent.addChild(preview)
        preview.view.frame = current.view.frame
        preview.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.view.isUserInteractionEnabled = false
        preview.view.accessibilityElementsHidden = true
        // Attached, opaque and rendered, but occluded by the real navigator.
        // isHidden / alpha=0 / an offscreen frame are deliberately not used.
        container.insertSubview(preview.view, belowSubview: current.view)
        preview.didMove(toParent: parent)
        preview.view.layoutIfNeeded()
        defer {
            if self.preview === preview { removePreview() }
        }
        try await ReaderWebViewport.waitUntilStable(preview)
        _ = try await preview.evaluateJavaScript(ReaderWebViewport.anchorScript(locator: source.locator, restore: true)).get()
        try await ReaderWebViewport.waitUntilStable(preview)
        let sourceSignature = try await viewportSignature(current)
        let previewSignature = try await viewportSignature(preview)
        guard sourceSignature == previewSignature else { throw ReaderWebViewport.FrameError.invalidAnchor }

        var next: ReaderPageFrame?
        if await preview.goForward(options: .init(animated: false)) {
            try await ReaderWebViewport.waitUntilStable(preview)
            next = try? await ReaderWebViewport.capture(preview, generation: generation, background: background)
        }
        try Task.checkCancellation()
        guard await preview.go(to: source.locator, options: .init(animated: false)) else {
            throw ReaderWebViewport.FrameError.invalidAnchor
        }
        _ = try await preview.evaluateJavaScript(ReaderWebViewport.anchorScript(locator: source.locator, restore: true)).get()
        try await ReaderWebViewport.waitUntilStable(preview)
        var previous: ReaderPageFrame?
        if await preview.goBackward(options: .init(animated: false)) {
            try await ReaderWebViewport.waitUntilStable(preview)
            previous = try? await ReaderWebViewport.capture(preview, generation: generation, background: background)
        }
        try Task.checkCancellation()
        guard sourceSignature == (try await viewportSignature(current)),
              source.viewport == current.view.bounds.size else { throw ReaderWebViewport.FrameError.stale }
        return ReaderPageFrames(previous: previous, current: source, next: next,
            rightToLeft: current.presentation.readingProgression == .rtl)
    }

    private func viewportSignature(_ navigator: EPUBNavigatorViewController) async throws -> String {
        let locator = try await ReaderWebViewport.exactLocator(in: navigator)
        let geometry = try await navigator.evaluateJavaScript("[innerWidth,innerHeight,scrollX,scrollY,document.documentElement.scrollWidth,getComputedStyle(document.documentElement).columnCount].join(':')").get()
        // The exact first visible character, not the preserved resume anchor.
        let data = try JSONSerialization.jsonObject(with: Data(locator.jsonString().utf8)) as? [String: Any]
        let locations = data?["locations"] as? [String: Any] ?? [:]
        let point = locations["koofyText"] ?? locations
        let identity = String(decoding: try JSONSerialization.data(withJSONObject: point, options: [.sortedKeys]), as: UTF8.self)
        return "\(locator.href)|\(identity)|\(geometry as? String ?? "")"
    }
}
