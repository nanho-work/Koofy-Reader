import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import UIKit

/// Full-screen UIKit host. The EPUB navigator owns all pagination and selection.
final class KoofyReaderViewController: UIViewController, EPUBNavigatorDelegate, UIGestureRecognizerDelegate {
    let request: ReaderLaunchRequest
    var onClosed: (() -> Void)?
    private let journal: ReaderCheckpointStore
    private let sendEvent: (ReaderEvent) -> Void
    private var speech: ReaderSpeech?
    private let speechButton = UIButton(type: .system)
    private let speechControls = UIStackView()
    private var speechTransportItem: UIBarButtonItem?
    private var speechFollowTask: Task<Void, Never>?
    private lazy var speechScrollPan = UIPanGestureRecognizer(target: self, action: #selector(speechManualScroll(_:)))
    private var publication: Publication?
    private var readerFonts: ReaderFonts?
    private var navigator: EPUBNavigatorViewController?
    private var preferences: ReaderPreferences
    private var lastLocator: Locator?
    private var restorationAnchor: Locator?
    private var sequence: Int64 = 0
    private var renderGeneration = 0
    private var layoutGeneration = 0
    private var captureGeneration = 0
    private var isReady = false
    private var renderFailed = false
    private var hasSentReady = false
    private var isClosing = false
    private var isRotating = false
    private var pendingKind = "ready"
    private var openingTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?
    private var navigationCompletion: ((Result<Void, Error>) -> Void)?
    private var readyTimeout: Task<Void, Never>?
    private var settingsCompletion: ((Result<Void, Error>) -> Void)?
    private let frameProvider = ReaderPageFrameProvider()
    private var frameTask: Task<Void, Never>?
    private var framePreparationSerial = 0
    private var pendingCurlRequest: (forward: Bool, deadline: Date)?
    private var lastTurnForward = true
    private var frameGeneration = 0
    private var pageTurnController: ReaderPageTurnController?
    private var turnBusy = false
    private var turnCommitInFlight = false
    private var needsTurnRestoration = false
    private var programmaticMovePending = false
    private var moveOperation = 0
    private lazy var pagePan = UIPanGestureRecognizer(target: self, action: #selector(pageDragged(_:)))
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let body = UIView()
    private let spreadDivider = UIView()
    private let toolbar = UIToolbar()
    private var bannerFooter: ReaderBannerFooter?
    private var bannerHeight: NSLayoutConstraint?
    private let progress = UILabel()
    private var progressItem: UIBarButtonItem!
    private var chromeVisible = true
    private var navigationHistory: [Locator] = []
    private var returnItem: UIBarButtonItem?
    private var nextPageItem: UIBarButtonItem?
    private var atBookEnd = false
    private var bookmarksJson: String

    init(request: ReaderLaunchRequest, journal: ReaderCheckpointStore, sendEvent: @escaping (ReaderEvent) -> Void) {
        self.request = request
        self.preferences = request.preferences
        self.bookmarksJson = request.bookmarksJson ?? "[]"
        self.journal = journal
        self.sendEvent = sendEvent
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(request:journal:sendEvent:)") }

    static func validate(_ preferences: ReaderPreferences) throws {
        func valid(_ value: Double?, _ range: ClosedRange<Double>) -> Bool {
            value.map { $0.isFinite && range.contains($0) } ?? true
        }
        guard valid(preferences.lineHeight, 1...2), valid(preferences.paragraphSpacing, 0...2), valid(preferences.pageMargins, 0.5...2),
              preferences.fontScale.isFinite, (0.5...3.0).contains(preferences.fontScale),
              (0...2).contains(preferences.columnCount),
              ["light", "sepia", "dark"].contains(preferences.theme),
              ["instant", "curl"].contains(preferences.pageTurnStyle ?? "instant"),
              ReaderFonts.isValidId(preferences.fontId) else {
            throw failure("invalid_preferences", "지원하지 않는 독서 설정입니다.")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = request.title
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "서재", style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "reader.close"
        configureMenu()
        body.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(body)
        view.addSubview(toolbar)
        spreadDivider.translatesAutoresizingMaskIntoConstraints = false
        spreadDivider.isUserInteractionEnabled = false
        spreadDivider.isAccessibilityElement = false
        spreadDivider.isHidden = true
        body.addSubview(spreadDivider)
        let footer = ReaderBannerFooter(controller: self, unitId: request.bannerAdUnitId, hiddenUntil: request.adHiddenUntilEpochMs)
        bannerFooter = footer
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)
        let footerHeight = footer.heightAnchor.constraint(equalToConstant: footer.desiredHeight)
        bannerHeight = footerHeight
        footer.onAdInteraction = { [weak self] in self?.speech?.pause() }
        footer.onHeightChanged = { [weak self] height in self?.resizeAdFooter(to: height) }
        pagePan.delegate = self
        pagePan.maximumNumberOfTouches = 1
        body.addGestureRecognizer(pagePan)
        progress.font = .preferredFont(forTextStyle: .caption1)
        progress.adjustsFontForContentSizeCategory = true
        progress.textAlignment = .center
        progress.numberOfLines = 2
        progress.lineBreakMode = .byTruncatingTail
        progress.widthAnchor.constraint(lessThanOrEqualToConstant: 140).isActive = true
        progress.text = "책을 여는 중"
        progress.accessibilityIdentifier = "reader.progress"
        progressItem = UIBarButtonItem(customView: progress)
        let returnButton = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), style: .plain, target: self, action: #selector(returnToReading))
        returnButton.accessibilityLabel = "이동 전 위치로"; returnButton.isEnabled = false; returnItem = returnButton
        let previous = UIBarButtonItem(title: "이전", style: .plain, target: self, action: #selector(previousTapped))
        previous.accessibilityIdentifier = "reader.previous"
        let next = UIBarButtonItem(title: "다음", style: .plain, target: self, action: #selector(nextTapped))
        next.accessibilityIdentifier = "reader.next"
        nextPageItem = next
        toolbar.items = [returnButton, previous, .flexibleSpace(), progressItem, .flexibleSpace(), next]
        spinner.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(spinner)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textAlignment = .center
        body.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            spreadDivider.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            spreadDivider.widthAnchor.constraint(equalToConstant: 1),
            spreadDivider.topAnchor.constraint(equalTo: body.topAnchor, constant: 24),
            spreadDivider.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -24),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            footerHeight,
            spinner.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: body.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: body.centerYAnchor),
        ])
        configureSpeechControls()
        spinner.startAnimating()
        NotificationCenter.default.addObserver(self, selector: #selector(flushBackground), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeForeground), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(motionPreferenceChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(motionPreferenceChanged), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        openingTask = Task { [weak self] in await self?.openPublication() }
        footer.resume()
    }

    private func resizeAdFooter(to height: CGFloat) {
        guard let constraint = bannerHeight, constraint.constant != height else { return }
        // Freeze the canonical locator before Auto Layout changes Readium's viewport.
        let anchor = restorationAnchor ?? lastLocator
        let restore = hasSentReady && !isClosing && !isRotating
        if restore {
            cancelUncommittedTurn()
            captureGeneration += 1
            captureTask?.cancel()
            restorationAnchor = anchor
            isRotating = true
        }
        constraint.constant = height
        view.layoutIfNeeded()
        if restore {
            isRotating = false
            do { try mountNavigator(at: anchor, kind: "locationChanged") }
            catch { report(error, code: "relayout_failed", fatal: true) }
        }
    }

    func updateAdHiddenUntil(_ epochMs: Int64?) { bannerFooter?.updateHiddenUntil(epochMs) }

    deinit {
        speech?.close()
        speechFollowTask?.cancel()
        bannerFooter?.dispose()
        openingTask?.cancel()
        captureTask?.cancel()
        moveTask?.cancel()
        frameTask?.cancel()
        readyTimeout?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func openPublication() async {
        do {
            readerFonts = try await Task.detached(priority: .userInitiated) { try ReaderFonts() }.value
            guard !Task.isCancelled, !isClosing else { return }
            let retriever = AssetRetriever(httpClient: OfflineHTTPClient())
            let opener = PublicationOpener(parser: EPUBParser())
            guard let file = FileURL(url: URL(fileURLWithPath: request.filePath)) else {
                throw failure("file_access", "책 파일 주소가 올바르지 않습니다.")
            }
            let asset = try await retriever.retrieve(url: file).get()
            let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
            guard !Task.isCancelled, !isClosing else { return }
            guard publication.conforms(to: .epub), !publication.isRestricted,
                  publication.metadata.layout != .fixed, !publication.readingOrder.isEmpty else {
                throw failure("unsupported_publication", "현재는 DRM 없는 리플로우 EPUB을 지원합니다.")
            }
            self.publication = publication
            speech = ReaderSpeech(publication: publication, request: request,
                visible: { [weak self] in
                    if let locator = self?.lastLocator { return locator }
                    return await self?.navigator?.firstVisibleElementLocator()
                },
                available: { [weak self] in self?.isReady == true && self?.isClosing == false && self?.presentedViewController == nil },
                changed: { [weak self] in self?.updateSpeechControls() },
                located: { [weak self] in self?.followSpeech($0) },
                message: { [weak self] in self?.speechMessage($0) })
            speech?.foreground(UIApplication.shared.applicationState == .active)
            let initial = try request.initialLocatorJson.map { try Locator(jsonString: $0) }
            if let initial { try validateLocation(initial) }
            try mountNavigator(at: initial, kind: "ready")
        } catch {
            guard !Task.isCancelled, !isClosing else { return }
            report(error, code: "open_failed", fatal: true)
        }
    }

    private func mountNavigator(at locator: Locator?, kind: String) throws {
        speech?.pause()
        guard let publication else { throw failure("reader_not_ready", "책을 여는 중입니다.") }
        moveOperation += 1
        moveTask?.cancel()
        programmaticMovePending = false
        invalidatePageTurns()
        needsTurnRestoration = false
        isReady = false
        renderFailed = false
        captureGeneration += 1
        renderGeneration += 1
        captureTask?.cancel()
        readyTimeout?.cancel()
        restorationAnchor = locator
        pendingKind = kind
        if let old = navigator {
            old.delegate = nil
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        let next = try makeNavigator(publication: publication, at: locator)
        next.delegate = self
        navigator = next
        addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        body.insertSubview(next.view, at: 0)
        NSLayoutConstraint.activate([
            next.view.topAnchor.constraint(equalTo: body.topAnchor),
            next.view.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            next.view.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])
        next.didMove(toParent: self)
        pagePan.isEnabled = !preferences.scroll
        statusLabel.text = nil
        spinner.startAnimating()
        configureMenu()
        let generation = renderGeneration
        readyTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self, self.renderGeneration == generation,
                  !self.isReady, !self.isClosing else { return }
            self.report(failure("render_timeout", "본문 표시가 완료되지 않았습니다. 책을 닫고 다시 열어 주세요."), code: "render_timeout", fatal: true)
        }
    }

    private func makeNavigator(publication: Publication, at locator: Locator?, preview: Bool = false) throws -> EPUBNavigatorViewController {
        try EPUBNavigatorViewController(publication: publication,
            initialLocation: locator, config: .init(
                preferences: epubPreferences(), disablePageTurnsWhileScrolling: true,
                contentInset: [.compact: (16, 16), .regular: (24, 24)],
                preloadPreviousPositionCount: preview ? 0 : 2,
                preloadNextPositionCount: preview ? 0 : 6,
                fontFamilyDeclarations: readerFonts?.declarations ?? [],
                // ReadiumCSS's bundled media query otherwise ignores an explicit
                // two-column preference below 60em (including portrait iPads).
                // Use its public reading-system configuration after our own
                // available-width check, preserving the engine's pagination.
                readiumCSSRSProperties: .init(
                    colCount: !preferences.scroll && preferences.columnCount != 1 && canShowSpread ? .two : .one,
                    // Safari needs a non-auto width to fragment a single column.
                    // Only spreads need to override Readium's width floor.
                    overrides: !preferences.scroll && preferences.columnCount != 1 && canShowSpread
                        ? ["--RS__colWidth": "auto"] : [:])) )
    }

    private func epubPreferences() -> EPUBPreferences {
        let columns: ColumnCount = preferences.scroll || preferences.columnCount == 1 || !canShowSpread
            ? .one : .two
        let palette = ReaderPalette.forTheme(preferences.theme)
        return EPUBPreferences(backgroundColor: Color(uiColor: palette.background),
            columnCount: columns, fontFamily: readerFonts?.family(preferences.fontId), fontSize: preferences.fontScale,
            lineHeight: preferences.lineHeight, pageMargins: preferences.pageMargins,
            paragraphSpacing: preferences.paragraphSpacing,
            publisherStyles: preferences.lineHeight == nil && preferences.paragraphSpacing == nil, scroll: preferences.scroll,
            textColor: Color(uiColor: palette.foreground),
            theme: Theme(rawValue: preferences.theme) ?? .light)
    }

    private var canShowSpread: Bool {
        let width = body.bounds.width > 0 ? body.bounds.width : view.bounds.width
        return width >= 700
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSpreadDivider()
    }

    private func updateSpreadDivider() {
        spreadDivider.isHidden = preferences.scroll || preferences.columnCount == 1 || !canShowSpread
        spreadDivider.backgroundColor = ReaderPalette.forTheme(preferences.theme).foreground.withAlphaComponent(0.095)
    }

    func apply(_ value: ReaderPreferences, completion: @escaping (Result<Void, Error>) -> Void) throws {
        guard isReady, !isClosing, !turnBusy else { throw failure("reader_not_ready", "본문 표시가 완료된 뒤 변경해 주세요.") }
        try Self.validate(value)
        let sameLayout = value.fontScale == preferences.fontScale && value.columnCount == preferences.columnCount &&
            value.scroll == preferences.scroll && value.theme == preferences.theme &&
            (value.fontId ?? "default") == (preferences.fontId ?? "default")
        if sameLayout {
            invalidatePageTurns()
            preferences = value
            try persist(kind: "preferencesChanged")
            completion(.success(()))
            preparePageTurns()
            return
        }
        // Recreate at an exact content anchor. This avoids saving transient page
        // starts while Readium's CSS layout is changing asynchronously.
        settingsCompletion?(.failure(failure("superseded", "새 설정으로 대체되었습니다.")))
        settingsCompletion = completion
        preferences = value
        do { try mountNavigator(at: lastLocator, kind: "preferencesChanged") }
        catch {
            settingsCompletion = nil
            throw error
        }
    }

    func go(to locator: Locator, turnForward: Bool? = nil, completion: @escaping (Result<Void, Error>) -> Void) throws {
        guard isReady, !isClosing, let navigator else { throw failure("reader_not_ready", "본문 표시가 완료된 뒤 이동해 주세요.") }
        speech?.userNavigation()
        try validateLocation(locator)
        if !turnCommitInFlight { invalidatePageTurns() }
        isReady = false
        captureGeneration += 1
        captureTask?.cancel()
        restorationAnchor = locator
        pendingKind = "locationChanged"
        navigationCompletion = completion
        programmaticMovePending = true
        moveOperation += 1
        let operation = moveOperation
        readyTimeout?.cancel()
        let navigationGeneration = renderGeneration
        readyTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, let self, self.renderGeneration == navigationGeneration,
                  self.navigationCompletion != nil, !self.isClosing else { return }
            self.moveTask?.cancel()
            self.moveOperation += 1
            self.captureTask?.cancel()
            self.captureGeneration += 1
            self.programmaticMovePending = false
            self.needsTurnRestoration = true
            self.finishNavigation(.failure(failure("navigation_timeout", "본문 이동을 완료하지 못했습니다.")))
            self.turnCommitInFlight = false
            self.turnBusy = false
            if UIApplication.shared.applicationState == .active { self.resumeForeground() }
        }
        moveTask = Task { [weak self, weak navigator] in
            guard let self, let navigator else { return }
            let success: Bool
            if let turnForward {
                // The cached target was obtained by this same one-viewport move.
                // Avoid Readium's quote search reselecting an earlier occurrence
                // inside a long/repeated paragraph during an ordinary page turn.
                success = turnForward ? await navigator.goForward(options: .init(animated: false))
                    : await navigator.goBackward(options: .init(animated: false))
            } else {
                success = await navigator.go(to: locator)
            }
            guard self.moveOperation == operation else { return }
            guard !Task.isCancelled, self.navigator === navigator, !self.isClosing else {
                self.finishNavigation(.failure(failure("navigation_cancelled", "본문 이동이 취소되었습니다.")))
                return
            }
            if success {
                self.programmaticMovePending = false
                self.capture(locator, from: navigator)
            } else {
                self.programmaticMovePending = false
                self.restorationAnchor = nil
                self.isReady = true
                self.finishNavigation(.failure(failure("navigation_failed", "요청한 본문 위치로 이동할 수 없습니다.")))
            }
        }
    }

    private func finishNavigation(_ result: Result<Void, Error>) {
        let completion = navigationCompletion
        navigationCompletion = nil
        completion?(result)
    }

    private func validateLocation(_ locator: Locator) throws {
        guard let publication,
              publication.readingOrder.firstIndexWithHREF(locator.href) != nil else {
            throw failure("invalid_locator", "이 책에 없는 본문 위치입니다.")
        }
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        guard let current = self.navigator, current === navigator, !isClosing, !isRotating, !renderFailed,
              !programmaticMovePending, current.viewport != nil else { return }
        capture(locator, from: current)
    }

    private func capture(_ fallback: Locator, from current: EPUBNavigatorViewController) {
        guard !renderFailed, !isClosing, navigator === current else { return }
        // Readium can repeat its last location while an image turn is in flight.
        // The main viewport has not moved until our commit; do not cancel that turn.
        if turnBusy && !turnCommitInFlight { return }
        captureGeneration += 1
        let token = captureGeneration
        let rendering = renderGeneration
        captureTask?.cancel()
        captureTask = Task { [weak self, weak current] in
            guard let self, let current else { return }
            let anchor = self.restorationAnchor ?? self.lastLocator
            let sameResource = anchor?.href == fallback.href
            var snapshot: [String: Any] = [:]
            do {
                if self.readerFonts?.family(self.preferences.fontId) != nil {
                    try await ReaderWebViewport.waitUntilStable(current)
                }
                let bundle = Bundle(for: KoofyReaderViewController.self)
                guard let resourceURL = bundle.url(forResource: "KoofyReaderAssets", withExtension: "bundle"),
                      let resources = Bundle(url: resourceURL),
                      let scriptURL = resources.url(forResource: "reader_anchor", withExtension: "js") else {
                    throw failure("anchor_script_missing", "읽기 위치 계산 파일을 찾지 못했습니다.")
                }
                let script = try String(contentsOf: scriptURL, encoding: .utf8)
                    .replacingOccurrences(of: "__KOOFY_RESTORE__", with: self.restorationAnchor != nil ? "true" : "false")
                    .replacingOccurrences(of: "__KOOFY_ANCHOR__", with: sameResource ? (try anchor?.jsonString() ?? "null") : "null")
                let value = try await current.evaluateJavaScript(script).get()
                guard let raw = value as? String, let data = raw.data(using: .utf8),
                      let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw failure("anchor_capture_failed", "본문 위치를 확인하지 못했습니다.")
                }
                snapshot = result
            } catch {
                guard !Task.isCancelled, self.captureGeneration == token,
                      self.renderGeneration == rendering, !self.renderFailed else { return }
                self.finishNavigation(.failure(error))
                self.report(error, code: "anchor_capture_failed", fatal: !self.hasSentReady)
                return
            }
            var exact = fallback
            if let locations = snapshot["locations"] as? [String: Any],
               let data = try? fallback.jsonString().data(using: .utf8),
               var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                var merged = json["locations"] as? [String: Any] ?? [:]
                merged.removeValue(forKey: "fragments")
                merged.merge(locations) { _, new in new }
                json["locations"] = merged
                json["text"] = snapshot["text"]
                if let encoded = try? JSONSerialization.data(withJSONObject: json),
                   let raw = String(data: encoded, encoding: .utf8),
                   let locator = try? Locator(jsonString: raw) { exact = locator }
            }
            guard !Task.isCancelled, self.captureGeneration == token,
                  self.renderGeneration == rendering, self.navigator === current,
                  !self.renderFailed, !self.isClosing else { return }
            if self.turnBusy && !self.turnCommitInFlight { return }
            if !self.turnCommitInFlight, let controller = self.pageTurnController,
               !controller.frames.matchesViewport(exact) {
                self.invalidatePageTurns()
            }
            let wasReady = self.isReady
            let previousLocator = self.lastLocator
            // Keep the requested anchor through relayout rather than repeatedly
            // moving it backwards to each newly calculated page start.
            if self.restorationAnchor != nil, snapshot["anchorVisible"] as? Bool == false {
                // WebKit may apply scrollToId on a later visual frame without a
                // second Readium location event. Retry the exact anchor until the
                // existing navigation/render deadline, instead of waiting forever
                // for another delegate notification or committing the wrong page.
                do { try await Task.sleep(nanoseconds: 40_000_000) }
                catch { return }
                guard !Task.isCancelled, self.captureGeneration == token, self.renderGeneration == rendering,
                      self.navigator === current, !self.isClosing else { return }
                self.capture(fallback, from: current)
                return
            }
            self.lastLocator = sameResource && snapshot["anchorVisible"] as? Bool == true ? anchor : exact
            self.restorationAnchor = nil
            self.isReady = true
            self.spinner.stopAnimating()
            self.readyTimeout?.cancel()
            self.atBookEnd = snapshot["resourceEnd"] as? Bool == true &&
                self.publication?.readingOrder.firstIndexWithHREF(fallback.href) == (self.publication?.readingOrder.count ?? 0) - 1
            let offerNext = self.atBookEnd && self.request.nextBookTitle != nil
            self.nextPageItem?.title = offerNext ? "이어서 읽기" : "다음"
            self.nextPageItem?.accessibilityLabel = offerNext ? "다음 권 \(self.request.nextBookTitle ?? "") 이어서 읽기" : "다음 페이지"
            self.progress.text = self.atBookEnd
                ? self.request.nextBookTitle.map { "마지막 페이지\n다음: \($0)" } ?? "마지막 페이지"
                : String(format: "%.1f%%", (fallback.locations.totalProgression ?? 0) * 100)
            self.progress.sizeToFit()
            do {
                let kind = self.hasSentReady ? (wasReady ? "locationChanged" : self.pendingKind) : "ready"
                // A delayed Readium location callback can describe the same
                // viewport already committed by an explicit jump. Do not turn
                // that no-op notification into another recovery checkpoint.
                if !wasReady || !self.hasSentReady || previousLocator != self.lastLocator ||
                    self.navigationCompletion != nil || self.settingsCompletion != nil {
                    try self.persist(kind: kind)
                }
                self.hasSentReady = true
                let completion = self.settingsCompletion
                self.settingsCompletion = nil
                completion?(.success(()))
                ReaderWebViewport.setPagingEnabled(self.preferences.scroll, in: current.view)
                self.finishNavigation(.success(()))
                if !self.turnCommitInFlight { self.preparePageTurns() }
            } catch {
                self.finishNavigation(.failure(error))
                self.report(error, code: "checkpoint_failed", fatal: false)
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        speech?.pause()
        cancelUncommittedTurn()
        layoutGeneration += 1
        let layout = layoutGeneration
        isRotating = true
        captureGeneration += 1
        captureTask?.cancel()
        restorationAnchor = lastLocator
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self, !self.isClosing, self.layoutGeneration == layout else { return }
            self.isRotating = false
            if self.hasSentReady {
                do {
                    try self.mountNavigator(at: self.lastLocator,
                        kind: self.isReady ? "locationChanged" : self.pendingKind)
                } catch { self.report(error, code: "relayout_failed", fatal: true) }
            }
        }
    }

    func close(nextBook: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        speech?.pause()
        speechFollowTask?.cancel()
        guard !isClosing else { completion(.failure(failure("reader_closing", "독서 화면을 닫는 중입니다."))); return }
        cancelUncommittedTurn()
        isClosing = true
        moveTask?.cancel()
        finishNavigation(.failure(failure("reader_closed", "독서 화면이 종료되었습니다.")))
        Task { [weak self] in
            guard let self else { return }
            await self.captureTask?.value
            do {
                var closedEvent = try self.checkpoint(kind: "closed")
                closedEvent.message = nextBook ? "nextBook" : nil
                self.openingTask?.cancel()
                self.readyTimeout?.cancel()
                self.settingsCompletion?(.failure(failure("reader_closed", "독서 화면이 종료되었습니다.")))
                self.settingsCompletion = nil
                self.navigationController?.dismiss(animated: true) {
                    self.onClosed?()
                    self.sendEvent(closedEvent)
                    completion(.success(()))
                }
            } catch {
                self.isClosing = false
                self.report(error, code: "checkpoint_failed", fatal: false)
                completion(.failure(error))
            }
        }
    }

    private func persist(kind: String) throws {
        sendEvent(try checkpoint(kind: kind))
    }

    private func checkpoint(kind: String) throws -> ReaderEvent {
        sequence += 1
        let event = ReaderEvent(protocolVersion: request.protocolVersion, sessionId: request.sessionId,
            sessionGeneration: request.sessionGeneration, publicationId: request.publicationId,
            contentRevision: request.contentRevision, sequence: sequence, kind: kind,
            locatorJson: try lastLocator?.jsonString(), preferences: preferences,
            errorCode: nil, message: nil, bookmarksJson: bookmarksJson)
        try journal.write(event)
        return event
    }

    private func report(_ error: Error, code: String, fatal: Bool) {
        if fatal {
            // A terminal deadline must stop restoration, not just hide its spinner.
            // Invalidate in-flight work before notifying any completion handlers.
            renderFailed = true
            isReady = false
            captureGeneration += 1
            renderGeneration += 1
            moveOperation += 1
            captureTask?.cancel()
            captureTask = nil
            moveTask?.cancel()
            moveTask = nil
            readyTimeout?.cancel()
            readyTimeout = nil
            restorationAnchor = nil
            programmaticMovePending = false
            needsTurnRestoration = false
            turnCommitInFlight = false
            turnBusy = false
            invalidatePageTurns()
            finishNavigation(.failure(error))
        }
        let message = (error as? PigeonError)?.message ?? "책을 처리하지 못했습니다: \(error.localizedDescription)"
        let effectiveCode = (error as? PigeonError)?.code ?? code
        sequence += 1
        sendEvent(ReaderEvent(protocolVersion: request.protocolVersion, sessionId: request.sessionId,
            sessionGeneration: request.sessionGeneration, publicationId: request.publicationId,
            contentRevision: request.contentRevision, sequence: sequence, kind: "error",
            locatorJson: try? lastLocator?.jsonString(), preferences: preferences,
            errorCode: effectiveCode, message: message))
        let completion = settingsCompletion
        settingsCompletion = nil
        completion?(.failure(error))
        if fatal {
            speech?.pause()
            isReady = false
            spinner.stopAnimating()
            statusLabel.text = message
            progress.text = "책을 열지 못함"
        } else if presentedViewController == nil {
            let alert = UIAlertController(title: code == "checkpoint_failed" ? "읽기 기록 저장 실패" : "독서 화면", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default))
            present(alert, animated: true)
        }
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) { report(error, code: "navigator_error", fatal: false) }
    func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
        report(error, code: "resource_failed", fatal: !hasSentReady)
    }
    func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
        let alert = UIAlertController(title: "외부 링크", message: "책 밖의 링크는 이 독서 화면에서 열지 않습니다.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        if presentedViewController == nil { present(alert, animated: true) }
    }

    @objc private func flushBackground() {
        speech?.foreground(false)
        speechFollowTask?.cancel()
        bannerFooter?.pause()
        guard hasSentReady, !isClosing else { return }
        cancelUncommittedTurn()
        do { try persist(kind: "locationChanged") }
        catch { report(error, code: "checkpoint_failed", fatal: false) }
    }
    @objc private func closeTapped() { close { _ in } }
    @objc private func previousTapped() {
        requestPageTurn(forward: false)
    }
    @objc private func nextTapped() {
        if atBookEnd && request.nextBookTitle != nil { nextBookTapped(); return }
        requestPageTurn(forward: true)
    }

    private var usesPageCurl: Bool {
        preferences.pageTurnStyle == "curl" && !preferences.scroll && !UIAccessibility.isReduceMotionEnabled &&
            !UIAccessibility.isVoiceOverRunning
    }

    private func invalidatePageTurns() {
        frameGeneration += 1
        framePreparationSerial += 1
        pendingCurlRequest = nil
        frameTask?.cancel()
        frameTask = nil
        frameProvider.removePreview()
        if let controller = pageTurnController {
            controller.invalidate()
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        pageTurnController = nil
        if !turnCommitInFlight { turnBusy = false }
    }

    private func preparePageTurns() {
        guard usesPageCurl, speech?.playing != true, isReady, !isClosing, !isRotating, !turnBusy,
              UIApplication.shared.applicationState == .active,
              let current = navigator, let publication else { return }
        frameTask?.cancel()
        framePreparationSerial += 1
        let serial = framePreparationSerial
        let generation = frameGeneration
        let palette = ReaderPalette.forTheme(preferences.theme)
        frameTask = Task { [weak self, weak current] in
            guard let self, let current else { return }
            defer {
                if self.framePreparationSerial == serial {
                    self.frameTask = nil
                    self.pendingCurlRequest = nil
                }
            }
            do {
                _ = try await self.frameProvider.prepare(current: current, parent: self,
                    container: self.body, generation: generation, background: palette.background,
                    existing: self.pageTurnController?.frames, preferForward: self.lastTurnForward,
                    publish: { [weak self, weak current] frames in
                        guard let self, let current, !Task.isCancelled, self.frameGeneration == generation,
                              self.framePreparationSerial == serial, self.navigator === current,
                              !self.isClosing else { return }
                        if let controller = self.pageTurnController { controller.refreshFrames() }
                        else { self.installPageTurnController(frames, current: current, background: palette.background) }
                        if let pending = self.pendingCurlRequest, !self.turnBusy,
                           self.pageTurnController?.canTurn(forward: pending.forward) == true {
                            self.pendingCurlRequest = nil
                            if Date() < pending.deadline { self.requestPageTurn(forward: pending.forward) }
                        }
                    }) { [weak self] locator in
                        guard let self else { throw CancellationError() }
                        return try self.makeNavigator(publication: publication, at: locator, preview: true)
                    }
            } catch {
                if !Task.isCancelled, self.framePreparationSerial == serial,
                   case ReaderWebViewport.FrameError.stale = error {
                    self.invalidatePageTurns()
                    self.preparePageTurns()
                }
                #if DEBUG
                if !Task.isCancelled { NSLog("Koofy page frame preparation unavailable: %@", String(describing: error)) }
                #endif
            }
        }
    }

    private func installPageTurnController(_ frames: ReaderPageFrames,
                                          current: EPUBNavigatorViewController, background: UIColor) {
        let controller = ReaderPageTurnController(frames: frames, background: background)
        controller.onBegin = { [weak self] in self?.speech?.userNavigation(); self?.turnBusy = true }
        controller.onCancel = { [weak self] in self?.turnBusy = false }
        controller.onCommit = { [weak self, weak controller] frame in
            guard let self, let controller, self.pageTurnController === controller,
                  self.frameGeneration == frame.generation, !self.isClosing,
                  !self.turnCommitInFlight else { return }
            self.lastTurnForward = controller.frames.next?.image === frame.image
            self.frameTask?.cancel()
            self.frameTask = nil
            self.framePreparationSerial += 1
            self.turnCommitInFlight = true
            do {
                try self.go(to: frame.locator, turnForward: self.lastTurnForward) { [weak self, weak controller] result in
                    guard let self, let controller else { return }
                    self.turnCommitInFlight = false
                    self.turnBusy = false
                    if case .success = result, self.pageTurnController === controller,
                       controller.frames.advance(to: frame) {
                        controller.rebase()
                    } else {
                        self.invalidatePageTurns()
                        if case let .failure(error) = result, !self.isClosing, !self.renderFailed, !self.needsTurnRestoration {
                            if !self.isReady {
                                self.needsTurnRestoration = true
                                self.resumeForeground()
                            }
                            self.report(error, code: "navigation_failed", fatal: false)
                        }
                    }
                    self.preparePageTurns()
                }
            } catch {
                self.turnCommitInFlight = false
                self.turnBusy = false
                controller.cancel()
                self.preparePageTurns()
                self.report(error, code: "navigation_failed", fatal: false)
            }
        }
        pageTurnController = controller
        addChild(controller)
        controller.view.frame = body.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        body.insertSubview(controller.view, aboveSubview: spreadDivider)
        controller.didMove(toParent: self)
    }

    /// All app-owned taps, buttons, keys and swipes use this policy. UIKit's
    /// edge drag commits through the same exact-locator navigation path.
    func requestPageTurn(forward: Bool) {
        speech?.userNavigation()
        guard isReady, !isClosing, !isRotating, !turnBusy, presentedViewController == nil,
              let current = navigator else { return }
        if usesPageCurl {
            if pageTurnController?.turn(forward: forward) == true { return }
            if pageTurnController?.frames.known(forward ? 1 : -1) == true { return }
            if frameTask != nil && pageTurnController?.frames.known(forward ? 1 : -1) != true {
                // Coalesce to one pending turn instead of flashing an immediate page
                // while the warm renderer prepares the next face.
                pendingCurlRequest = (forward, Date().addingTimeInterval(5))
                return
            }
        }
        invalidatePageTurns()
        turnBusy = true
        isReady = false
        programmaticMovePending = true
        moveOperation += 1
        let operation = moveOperation
        moveTask = Task { [weak self, weak current] in
            guard let self, let current else { return }
            let source = current.currentLocation
            let moved = forward ? await current.goForward(options: .init(animated: false))
                : await current.goBackward(options: .init(animated: false))
            if moved {
                // Readium updates currentLocation asynchronously after its go
                // operation. Wait for that update rather than combine a new
                // DOM anchor with the previous chapter's HREF/progression.
                for _ in 0..<100 where current.currentLocation == source {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
            guard !Task.isCancelled, self.moveOperation == operation, self.navigator === current, !self.isClosing else { return }
            self.programmaticMovePending = false
            self.turnBusy = false
            if moved, let locator = current.currentLocation, locator != source { self.capture(locator, from: current) }
            else { self.isReady = true; self.preparePageTurns() }
        }
    }

    private func cancelUncommittedTurn() {
        if turnCommitInFlight {
            needsTurnRestoration = true
            turnCommitInFlight = false
            moveTask?.cancel()
            moveOperation += 1
            programmaticMovePending = false
            captureTask?.cancel()
            captureGeneration += 1
            restorationAnchor = lastLocator
            isReady = false
            finishNavigation(.failure(failure("navigation_cancelled", "본문 이동이 취소되었습니다.")))
        }
        invalidatePageTurns()
        turnBusy = false
    }

    @objc private func resumeForeground() {
        speech?.foreground(true)
        guard !isClosing, !renderFailed else { return }
        bannerFooter?.resume()
        if needsTurnRestoration {
            needsTurnRestoration = false
            do { try mountNavigator(at: lastLocator, kind: "locationChanged") }
            catch { report(error, code: "relayout_failed", fatal: true) }
        } else { preparePageTurns() }
    }

    @objc private func motionPreferenceChanged() {
        cancelUncommittedTurn()
        if needsTurnRestoration { resumeForeground() }
        else { preparePageTurns() }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        cancelUncommittedTurn()
        if needsTurnRestoration, UIApplication.shared.applicationState == .active { resumeForeground() }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === speechScrollPan || otherGestureRecognizer === speechScrollPan
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === speechScrollPan { return preferences.scroll }
        guard gestureRecognizer === pagePan, !preferences.scroll, isReady, !turnBusy,
              !isClosing, navigator?.currentSelection == nil, presentedViewController == nil else { return false }
        let velocity = pagePan.velocity(in: body)
        guard abs(velocity.x) > abs(velocity.y) else { return false }
        let x = pagePan.location(in: body).x - pagePan.translation(in: body).x
        let edge = min(80, body.bounds.width * 0.2)
        if usesPageCurl, let controller = pageTurnController, x < edge || x > body.bounds.width - edge {
            let forward = controller.frames.rightToLeft ? x < edge : x > body.bounds.width - edge
            if controller.canTurn(forward: forward) { return false }
        }
        return true
    }

    @objc private func pageDragged(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let distance = recognizer.translation(in: body).x
        let velocity = recognizer.velocity(in: body).x
        guard abs(distance) > min(80, body.bounds.width * 0.18) || abs(velocity) > 500 else { return }
        let physicalForward = distance < 0
        requestPageTurn(forward: navigator?.presentation.readingProgression == .rtl ? !physicalForward : physicalForward)
    }

    func navigator(_ navigator: VisualNavigator, didPressKey event: KeyEvent) {
        guard event.phase == .down, event.modifiers.isEmpty else { return }
        switch event.key {
        case .arrowRight: requestPageTurn(forward: navigator.presentation.readingProgression != .rtl)
        case .arrowLeft: requestPageTurn(forward: navigator.presentation.readingProgression == .rtl)
        case .space, .pageDown: requestPageTurn(forward: true)
        case .pageUp: requestPageTurn(forward: false)
        default: break
        }
    }

    private func configureSpeechControls() {
        speechButton.translatesAutoresizingMaskIntoConstraints = false
        speechButton.layer.cornerRadius = 24
        speechButton.accessibilityIdentifier = "reader.speech.play"
        speechButton.addTarget(self, action: #selector(speechTapped), for: .touchUpInside)
        speechButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(speechLongPressed(_:))))
        view.addSubview(speechButton)
        speechControls.translatesAutoresizingMaskIntoConstraints = false
        speechControls.axis = .horizontal
        speechControls.spacing = 0
        speechControls.layer.cornerRadius = 12
        func control(_ symbol: String, _ label: String, _ action: Selector) {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.accessibilityLabel = label
            button.addTarget(self, action: action, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 48).isActive = true
            speechControls.addArrangedSubview(button)
        }
        control("backward.end.fill", "이전 문장", #selector(speechPrevious))
        control("forward.end.fill", "다음 문장", #selector(speechNext))
        control("slider.horizontal.3", "듣기 설정", #selector(showSpeechSettings))
        speechTransportItem = UIBarButtonItem(customView: speechControls)
        NSLayoutConstraint.activate([
            speechButton.topAnchor.constraint(equalTo: body.topAnchor, constant: 8),
            speechButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            speechButton.widthAnchor.constraint(equalToConstant: 48), speechButton.heightAnchor.constraint(equalToConstant: 48),
            speechControls.widthAnchor.constraint(equalToConstant: 144),
            speechControls.heightAnchor.constraint(equalToConstant: 48),
            toolbar.heightAnchor.constraint(equalToConstant: 48),
        ])
        speechScrollPan.cancelsTouchesInView = false
        speechScrollPan.delegate = self
        body.addGestureRecognizer(speechScrollPan)
        updateSpeechControls()
        applyChromeTheme()
    }
    private func updateSpeechControls() {
        let playing = speech?.playing == true
        speechButton.setImage(UIImage(systemName: speech?.busy == true ? "hourglass" : playing ? "pause.fill" : "play.fill"), for: .normal)
        speechButton.accessibilityLabel = playing || speech?.busy == true ? "책 읽어주기 일시정지" : "책 읽어주기 재생"
        speechButton.isHidden = !chromeVisible
        let transport = playing || speech?.busy == true
        if let item = speechTransportItem, var items = toolbar.items,
           let index = items.firstIndex(where: { $0 === progressItem || $0 === item }) {
            items[index] = transport ? item : progressItem
            toolbar.items = items
        }
        for button in speechControls.arrangedSubviews.prefix(2) { button.isUserInteractionEnabled = playing; button.alpha = playing ? 1 : 0.4 }
    }
    @objc private func speechTapped() { speech?.toggle() }
    @objc private func speechPrevious() { speech?.skip(false) }
    @objc private func speechNext() { speech?.skip(true) }
    @objc private func speechLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began { showSpeechSettings() }
    }
    @objc private func speechManualScroll(_ recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .began { speech?.userNavigation() }
    }
    @objc private func showSpeechSettings() {
        guard let speech, presentedViewController == nil, !isClosing else { return }
        speech.pause()
        let sheet = UINavigationController(rootViewController: ReaderSpeechSettingsViewController(speech: speech, palette: ReaderPalette.forTheme(preferences.theme)))
        sheet.modalPresentationStyle = .pageSheet
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        present(sheet, animated: true)
    }
    private func speechMessage(_ message: String) {
        guard !isClosing, UIApplication.shared.applicationState == .active else { return }
        let alert = UIAlertController(title: "책 읽어주기", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .cancel))
        (presentedViewController ?? self).present(alert, animated: true)
    }
    private func followSpeech(_ locator: Locator?) {
        guard let navigator else { return }
        navigator.apply(decorations: locator.map { [Decoration(id: "speech", locator: $0,
            style: .highlight(tint: UIColor.systemYellow.withAlphaComponent(0.25)))] } ?? [], in: "koofy.speech")
        speechFollowTask?.cancel()
        guard let locator, speech?.follow == true, speech?.playing == true, isReady, !isClosing, !turnBusy else { return }
        speechFollowTask = Task { [weak self, weak navigator] in
            guard let self, let navigator, !Task.isCancelled, self.speech?.playing == true,
                  UIApplication.shared.applicationState == .active else { return }
            self.invalidatePageTurns()
            _ = await navigator.go(to: locator, options: .init(animated: false))
        }
    }

    private func configureMenu() {
        overrideUserInterfaceStyle = preferences.theme == "dark" ? .dark : .light
        navigationController?.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        let settings = UIBarButtonItem(image: UIImage(systemName: "textformat.size"), style: .plain,
            target: self, action: #selector(preferencesTapped(_:)))
        settings.accessibilityLabel = "독서 설정"
        settings.accessibilityIdentifier = "reader.preferences"
        let contents = UIBarButtonItem(title: "목차", style: .plain, target: self, action: #selector(contentsTapped))
        contents.accessibilityIdentifier = "reader.contents"
        let tools = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(toolsTapped(_:)))
        tools.accessibilityLabel = "본문 검색 · 책갈피"
        navigationItem.rightBarButtonItems = [settings, contents, tools]
        if request.nextBookTitle != nil {
            let next = UIBarButtonItem(title: "다음 권", style: .plain,
                target: self, action: #selector(nextBookTapped))
            navigationItem.rightBarButtonItems?.append(next)
        }
        // Keep the navigation bar height stable across preference changes.
        navigationItem.prompt = nil
        applyChromeTheme()
    }

    @objc private func nextBookTapped() {
        speech?.pause()
        guard isReady, !isClosing, !turnBusy, presentedViewController == nil, let title = request.nextBookTitle else { return }
        let alert = UIAlertController(title: "다음 권 읽기", message: title, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "열기", style: .default) { [weak self] _ in
            self?.close(nextBook: true) { _ in }
        })
        present(alert, animated: true)
    }

    @objc private func preferencesTapped(_ sender: UIBarButtonItem) {
        speech?.pause()
        guard isReady, !isClosing, presentedViewController == nil else { return }
        let settings = ReaderSettingsViewController(preferences: preferences,
            fontIds: readerFonts?.optionIds ?? ReaderFonts.ids, fontLabels: readerFonts?.optionLabels ?? ReaderFonts.labels) { [weak self] value, completion in
            guard let self else { return }
            do { try self.apply(value, completion: completion) }
            catch { completion(.failure(error)) }
        }
        settings.onSpeech = { [weak self, weak settings] in
            settings?.dismiss(animated: true) { self?.showSpeechSettings() }
        }
        let sheet = UINavigationController(rootViewController: settings)
        if traitCollection.horizontalSizeClass == .regular {
            sheet.modalPresentationStyle = .popover
            sheet.preferredContentSize = CGSize(width: 380, height: 580)
            sheet.popoverPresentationController?.barButtonItem = sender
        } else {
            sheet.modalPresentationStyle = .pageSheet
            if #available(iOS 15.0, *) {
                sheet.sheetPresentationController?.detents = [.medium(), .large()]
                sheet.sheetPresentationController?.prefersGrabberVisible = true
            }
        }
        navigator?.resignFirstResponder()
        view.window?.endEditing(true)
        present(sheet, animated: true)
    }

    private func applyChromeTheme() {
        updateSpreadDivider()
        let palette = ReaderPalette.forTheme(preferences.theme)
        view.backgroundColor = palette.background
        body.backgroundColor = palette.background
        toolbar.backgroundColor = palette.background
        bannerFooter?.applyPalette(palette)
        speechButton.backgroundColor = palette.panel.withAlphaComponent(0.4)
        speechButton.tintColor = palette.foreground
        speechControls.backgroundColor = palette.background
        speechControls.tintColor = palette.foreground
        progress.textColor = palette.secondary
        statusLabel.textColor = palette.foreground
        spinner.color = palette.accent
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = palette.background
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: palette.foreground]
        navigationController?.navigationBar.standardAppearance = navigation
        navigationController?.navigationBar.scrollEdgeAppearance = navigation
        navigationController?.navigationBar.compactAppearance = navigation
        navigationController?.navigationBar.tintColor = palette.accent
        navigationController?.view.backgroundColor = palette.background
        let appearance = UIToolbarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = palette.background
        appearance.shadowColor = .clear
        toolbar.standardAppearance = appearance
        toolbar.compactAppearance = appearance
        if #available(iOS 15.0, *) { toolbar.scrollEdgeAppearance = appearance }
        toolbar.tintColor = palette.accent
        setNeedsStatusBarAppearanceUpdate()
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        let edge = max(80, navigator.view.bounds.width * 0.3)
        guard presentedViewController == nil, !turnBusy else { return }
        if point.x <= edge || point.x >= navigator.view.bounds.width - edge {
            guard !preferences.scroll, self.navigator?.currentSelection == nil else { return }
            let physicalForward = point.x >= navigator.view.bounds.width - edge
            requestPageTurn(forward: navigator.presentation.readingProgression == .rtl ? !physicalForward : physicalForward)
            return
        }
        chromeVisible.toggle()
        // Preserve layout/safe-area geometry; visibility cannot change pagination.
        navigationController?.navigationBar.alpha = chromeVisible ? 1 : 0
        navigationController?.navigationBar.accessibilityElementsHidden = !chromeVisible
        toolbar.alpha = chromeVisible ? 1 : 0
        toolbar.accessibilityElementsHidden = !chromeVisible
        updateSpeechControls()
    }

    private func jumpFromTools(_ target: Locator) {
        guard isReady, !isClosing, !turnBusy, let source = lastLocator else { return }
        do {
            try go(to: target) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    self.navigationHistory.append(source)
                    if self.navigationHistory.count > 20 { self.navigationHistory.removeFirst() }
                    self.returnItem?.isEnabled = true
                } else if case let .failure(error) = result { self.report(error, code: "navigation_failed", fatal: false) }
            }
        } catch { report(error, code: "navigation_failed", fatal: false) }
    }
    @objc private func returnToReading() {
        guard isReady, !isClosing, !turnBusy, let target = navigationHistory.last else { return }
        do {
            try go(to: target) { [weak self] result in
                guard let self else { return }
                if case .success = result { self.navigationHistory.removeLast(); self.returnItem?.isEnabled = !self.navigationHistory.isEmpty }
                else if case let .failure(error) = result { self.report(error, code: "navigation_failed", fatal: false) }
            }
        } catch { report(error, code: "navigation_failed", fatal: false) }
    }
    private func saveBookmarks(_ rows: [ReaderBookmark]) throws {
        let previous = bookmarksJson
        bookmarksJson = try ReaderBookmark.encode(rows)
        do { try persist(kind: "locationChanged") }
        catch { bookmarksJson = previous; throw error }
    }
    private func presentTool(_ controller: UIViewController) {
        speech?.pause()
        (controller as? ReaderToolTableController)?.palette = ReaderPalette.forTheme(preferences.theme)
        let sheet = UINavigationController(rootViewController: controller)
        sheet.overrideUserInterfaceStyle = preferences.theme == "dark" ? .dark : .light
        sheet.modalPresentationStyle = .pageSheet
        present(sheet, animated: true)
    }
    @objc private func toolsTapped(_ sender: UIBarButtonItem) {
        guard isReady, !isClosing, !turnBusy, presentedViewController == nil, let publication else { return }
        let menu = UIAlertController(title: "찾기 · 책갈피", message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "본문 검색", style: .default) { [weak self] _ in
            self?.presentTool(ReaderSearchViewController(publication: publication) { [weak self] location in self?.jumpFromTools(location) })
        })
        menu.addAction(UIAlertAction(title: "현재 위치에 책갈피 추가", style: .default) { [weak self] _ in self?.addBookmark() })
        menu.addAction(UIAlertAction(title: "책갈피 목록", style: .default) { [weak self] _ in
            guard let self else { return }
            do { self.presentTool(ReaderBookmarksViewController(rows: try ReaderBookmark.decode(self.bookmarksJson), save: { [weak self] rows in try self?.saveBookmarks(rows) }, jump: { [weak self] location in self?.jumpFromTools(location) })) }
            catch { self.report(error, code: "bookmarks_failed", fatal: false) }
        })
        menu.addAction(UIAlertAction(title: "닫기", style: .cancel))
        menu.popoverPresentationController?.barButtonItem = sender
        present(menu, animated: true)
    }
    private func addBookmark() {
        guard isReady, !isClosing, let locator = lastLocator else { return }
        do {
            let rows = try ReaderBookmark.decode(bookmarksJson)
            guard rows.count < 100 else { throw failure("bookmark_limit", "책갈피는 책마다 100개까지 저장할 수 있습니다.") }
            guard !rows.contains(where: { $0.locator == locator }) else { throw failure("bookmark_exists", "이미 저장한 위치입니다.") }
            let alert = UIAlertController(title: "책갈피 이름", message: nil, preferredStyle: .alert)
            alert.addTextField { $0.text = String(ReaderBookmark.snippet(locator).prefix(120)) }
            alert.addAction(UIAlertAction(title: "취소", style: .cancel))
            alert.addAction(UIAlertAction(title: "저장", style: .default) { [weak self, weak alert] _ in
                guard let self else { return }
                let label = ReaderBookmark.label(alert?.textFields?.first?.text ?? "책갈피")
                do { try self.saveBookmarks(rows + [ReaderBookmark(id: UUID().uuidString, label: label.isEmpty ? "책갈피" : label, locator: locator)]) }
                catch { self.report(error, code: "bookmark_save_failed", fatal: false) }
            })
            present(alert, animated: true)
        } catch { report(error, code: "bookmark_failed", fatal: false) }
    }

    @objc private func contentsTapped() {
        speech?.pause()
        guard isReady, let publication, presentedViewController == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let toc = try await publication.tableOfContents().get()
                guard !self.isClosing, self.presentedViewController == nil else { return }
                let links = toc.isEmpty ? publication.readingOrder : toc
                let contents = KoofyContentsViewController(links: links, theme: self.preferences.theme) { [weak self] link in
                    guard let self else { return }
                    Task {
                        guard let locator = await publication.locate(link) else { return }
                        self.jumpFromTools(locator)
                    }
                }
                let sheet = UINavigationController(rootViewController: contents)
                sheet.modalPresentationStyle = .pageSheet
                self.present(sheet, animated: true)
            } catch { self.report(error, code: "contents_failed", fatal: false) }
        }
    }

}

/// Local-only parser access. Import validation also rejects remote EPUB resources.
private final class OfflineHTTPClient: HTTPClient {
    func stream(request: HTTPRequestConvertible,
                consume: @escaping (Data, Double?) -> HTTPResult<Void>) async -> HTTPResult<HTTPResponse> {
        .failure(.offline(nil))
    }
}

private final class KoofyContentsViewController: UITableViewController {
    private let rows: [(Link, Int)]
    private let choose: (Link) -> Void
    private let theme: String

    init(links: [Link], theme: String, choose: @escaping (Link) -> Void) {
        func flatten(_ links: [Link], depth: Int) -> [(Link, Int)] {
            links.flatMap { [($0, depth)] + flatten($0.children, depth: depth + 1) }
        }
        self.rows = flatten(links, depth: 0)
        self.choose = choose
        self.theme = theme
        super.init(style: .insetGrouped)
        title = "목차"
    }

    required init?(coder: NSCoder) { fatalError("Use init(links:choose:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let palette = ReaderPalette.forTheme(theme)
        overrideUserInterfaceStyle = theme == "dark" ? .dark : .light
        navigationController?.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        tableView.backgroundColor = palette.background
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = palette.background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: palette.foreground]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = palette.accent
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "닫기", style: .done,
            target: self, action: #selector(closeSheet))
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let palette = ReaderPalette.forTheme(theme)
        cell.backgroundColor = palette.panel
        cell.textLabel?.textColor = palette.foreground
        cell.tintColor = palette.accent
        let (link, depth) = rows[indexPath.row]
        cell.textLabel?.text = link.title ?? "항목 \(indexPath.row + 1)"
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.indentationLevel = min(depth, 5)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let link = rows[indexPath.row].0
        dismiss(animated: true) { self.choose(link) }
    }

    @objc private func closeSheet() { dismiss(animated: true) }
}
