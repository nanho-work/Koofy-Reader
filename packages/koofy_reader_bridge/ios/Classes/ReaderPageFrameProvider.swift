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

/// One layout generation, with a rolling window of at most five viewports.
@MainActor
final class ReaderPageFrames {
    private var pages: [Int: ReaderPageFrame]
    private var boundaries = Set<Int>()
    private var center = 0
    let rightToLeft: Bool
    var current: ReaderPageFrame { pages[center]! }
    var next: ReaderPageFrame? { frame(at: 1) }
    var previous: ReaderPageFrame? { frame(at: -1) }

    init(previous: ReaderPageFrame?, current: ReaderPageFrame, next: ReaderPageFrame?, rightToLeft: Bool) {
        pages = [0: current]
        pages[-1] = previous
        pages[1] = next
        self.rightToLeft = rightToLeft
    }
    func matchesViewport(_ locator: Locator) -> Bool {
        guard current.locator.href == locator.href else { return false }
        func point(_ value: Locator) -> NSDictionary? {
            guard let data = try? value.jsonString().data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let locations = json["locations"] as? [String: Any],
                  let point = locations["koofyText"] as? [String: Any] else { return nil }
            return NSDictionary(dictionary: point)
        }
        if let a = point(current.locator), let b = point(locator) { return a == b }
        return current.locator.locations.progression == locator.locations.progression
    }

    func frame(at offset: Int) -> ReaderPageFrame? { pages[center + offset] }
    func known(_ offset: Int) -> Bool { pages[center + offset] != nil || boundaries.contains(center + offset) }
    func put(_ frame: ReaderPageFrame?, at offset: Int) {
        if let frame { pages[center + offset] = frame }
        else { boundaries.insert(center + offset) }
    }
    @discardableResult
    func advance(to frame: ReaderPageFrame) -> Bool {
        guard let entry = pages.first(where: { $0.value.image === frame.image }) else { return false }
        center = entry.key
        pages = pages.filter { abs($0.key - center) <= 2 }
        boundaries = boundaries.filter { abs($0 - center) <= 2 }
        return true
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
        // Five cached viewports stay under ~48 MiB before temporary UIKit
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
                 existing: ReaderPageFrames? = nil, preferForward: Bool = true,
                 publish: (ReaderPageFrames) -> Void = { _ in },
                 factory: (Locator) throws -> EPUBNavigatorViewController) async throws -> ReaderPageFrames {
        try await ReaderWebViewport.waitUntilStable(current)
        let frames: ReaderPageFrames
        if let existing {
            let actual = try await ReaderWebViewport.exactLocator(in: current)
            guard try point(actual) == point(existing.current.locator),
                  existing.current.viewport == current.view.bounds.size else {
                throw ReaderWebViewport.FrameError.stale
            }
            frames = existing
        } else {
            let source = try await ReaderWebViewport.capture(current, generation: generation, background: background)
            frames = ReaderPageFrames(previous: nil, current: source, next: nil,
                rightToLeft: current.presentation.readingProgression == .rtl)
        }
        let source = frames.current
        let renderer: EPUBNavigatorViewController
        if let preview { renderer = preview }
        else {
            renderer = try factory(source.locator)
            preview = renderer
            parent.addChild(renderer)
            renderer.view.frame = current.view.frame
            renderer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            renderer.view.isUserInteractionEnabled = false
            renderer.view.accessibilityElementsHidden = true
            container.insertSubview(renderer.view, belowSubview: current.view)
            renderer.didMove(toParent: parent)
            renderer.view.layoutIfNeeded()
            try await ReaderWebViewport.waitUntilStable(renderer)
        }
        if existing == nil {
            try await align(renderer, to: source.locator)
            let sourceSignature = try await viewportSignature(current)
            let previewSignature = try await viewportSignature(renderer)
            guard sourceSignature == previewSignature else { throw ReaderWebViewport.FrameError.invalidAnchor }
        }
        publish(frames)
        let order = preferForward ? [1, 2, -1, -2] : [-1, -2, 1, 2]
        for offset in order where !frames.known(offset) {
            try Task.checkCancellation()
            let forward = offset > 0
            guard let base = frames.frame(at: offset - (forward ? 1 : -1)) else {
                frames.put(nil, at: offset)
                publish(frames)
                continue
            }
            try await align(renderer, to: base.locator)
            let moved = forward ? await renderer.goForward(options: .init(animated: false))
                : await renderer.goBackward(options: .init(animated: false))
            if moved {
                try await ReaderWebViewport.waitUntilStable(renderer)
                let frame = try await ReaderWebViewport.capture(renderer, generation: generation, background: background)
                // Some Readium boundaries accept a move without changing the
                // visible text. Do not cache the current page as its own neighbor.
                frames.put(try point(frame.locator) == point(base.locator) ? nil : frame, at: offset)
            } else { frames.put(nil, at: offset) }
            try Task.checkCancellation()
            publish(frames)
        }
        return frames
    }

    private func align(_ navigator: EPUBNavigatorViewController, to locator: Locator) async throws {
        let current = try await ReaderWebViewport.exactLocator(in: navigator)
        if try point(current) == point(locator) { return }
        // These are exact viewport-start locators from this layout. Avoid quote
        // search when returning a warm preview to a repeated/long paragraph:
        // use its verified progression, then check/restore the precise DOM point.
        guard var json = try JSONSerialization.jsonObject(with: Data(locator.jsonString().utf8)) as? [String: Any] else {
            throw ReaderWebViewport.FrameError.invalidAnchor
        }
        json.removeValue(forKey: "text")
        if var locations = json["locations"] as? [String: Any] {
            locations.removeValue(forKey: "fragments")
            json["locations"] = locations
        }
        let page = try Locator(jsonString: String(decoding: JSONSerialization.data(withJSONObject: json), as: UTF8.self))
        guard await navigator.go(to: page, options: .init(animated: false)) else {
            throw ReaderWebViewport.FrameError.invalidAnchor
        }
        for _ in 0..<4 {
            try await ReaderWebViewport.waitUntilStable(navigator)
            let actual = try await ReaderWebViewport.exactLocator(in: navigator)
            if try point(actual) == point(locator) { return }
            _ = try await navigator.evaluateJavaScript(ReaderWebViewport.anchorScript(locator: locator, restore: true)).get()
        }
        throw ReaderWebViewport.FrameError.invalidAnchor
    }

    private func point(_ locator: Locator) throws -> String {
        let data = try JSONSerialization.jsonObject(with: Data(locator.jsonString().utf8)) as? [String: Any]
        let locations = data?["locations"] as? [String: Any] ?? [:]
        let point = locations["koofyText"] ?? locations
        return "\(locator.href)|" + String(decoding: try JSONSerialization.data(withJSONObject: point, options: [.sortedKeys]), as: UTF8.self)
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
