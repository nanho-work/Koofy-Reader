import Foundation
import ReadiumShared
import ReadiumNavigator
import ReadiumZIPFoundation
import UIKit
import XCTest
@testable import koofy_reader_bridge

final class RunnerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testOldAcknowledgementCannotDeleteNewLocation() throws {
        let journal = try ReaderCheckpointStore(directory: directory)
        try journal.write(event(sequence: 1))
        try journal.write(event(sequence: 2))
        try journal.acknowledge(sessionId: "session", sequence: 1)
        XCTAssertEqual(try journal.pending().map(\.sequence), [2])
        try journal.acknowledge(sessionId: "session", sequence: 2)
        XCTAssertTrue(try journal.pending().isEmpty)
    }

    func testCheckpointSurvivesColdRestartWithFullLocatorAndPreferences() throws {
        let original = event(sequence: 7)
        try ReaderCheckpointStore(directory: directory).write(original)
        let restored = try XCTUnwrap(ReaderCheckpointStore(directory: directory).pending().first)
        XCTAssertEqual(restored, original)
    }

    func testCorruptLatestRecordFallsBackToPreviousAtomicCheckpoint() throws {
        let journal = try ReaderCheckpointStore(directory: directory)
        try journal.write(event(sequence: 1))
        try journal.write(event(sequence: 2))
        let latest = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        try Data("interrupted".utf8).write(to: latest)
        XCTAssertEqual(try journal.pending().map(\.sequence), [1])
        try journal.acknowledge(sessionId: "session", sequence: 1)
        XCTAssertTrue(try journal.pending().isEmpty)
    }

    func testAnotherSessionAcknowledgementDoesNotDeleteRecord() throws {
        let journal = try ReaderCheckpointStore(directory: directory)
        try journal.write(event(sequence: 1))
        try journal.acknowledge(sessionId: "different", sequence: 1)
        XCTAssertEqual(try journal.pending().count, 1)
    }

    @MainActor
    func testReadiumRendersRelayoutsAndRestoresBeforeClosing() async throws {
        let file = try await makeEPUB()
        let request = ReaderLaunchRequest(protocolVersion: 1, sessionId: "render-session",
            sessionGeneration: 8, publicationId: "render-fixture", contentRevision: "fixture-v1",
            filePath: file.path, title: "한글 독서 검증",
            preferences: ReaderPreferences(fontScale: 1, columnCount: 1, scroll: false, theme: "light"))
        let ready = expectation(description: "Visible Readium viewport")
        var events: [ReaderEvent] = []
        let moved = expectation(description: "Moved to paragraph sixty")
        var awaitingMove = false
        let reader = KoofyReaderViewController(request: request,
            journal: try ReaderCheckpointStore(directory: directory.appendingPathComponent("journal"))) { event in
                events.append(event)
                if event.kind == "ready" { ready.fulfill() }
                if event.kind == "error" { XCTFail(event.message ?? "Reader error") }
                if awaitingMove, event.kind == "locationChanged" {
                    awaitingMove = false
                    moved.fulfill()
                }
            }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let presenter = try XCTUnwrap(window.rootViewController)
        let navigation = UINavigationController(rootViewController: reader)
        navigation.modalPresentationStyle = .fullScreen
        presenter.present(navigation, animated: false)
        await fulfillment(of: [ready], timeout: 35)
        let first = try XCTUnwrap(events.first { $0.kind == "ready" }?.locatorJson)
        let firstLocator = try Locator(jsonString: first)
        let middle = Locator(href: firstLocator.href, mediaType: firstLocator.mediaType,
            locations: .init(fragments: ["p60"]))
        awaitingMove = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do { try reader.go(to: middle) { continuation.resume(with: $0) } }
            catch { continuation.resume(throwing: error) }
        }
        await fulfillment(of: [moved], timeout: 10)
        let middleJSON = try XCTUnwrap(events.last?.locatorJson)
        let visibleBefore = try await paragraphSixtyIsVisible(in: reader)
        XCTAssertTrue(visibleBefore, "Requested paragraph must actually be on screen")
        let preferences = ReaderPreferences(fontScale: 1.5, columnCount: 2, scroll: false, theme: "sepia")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do { try reader.apply(preferences) { continuation.resume(with: $0) } }
            catch { continuation.resume(throwing: error) }
        }
        XCTAssertEqual(events.last?.kind, "preferencesChanged")
        XCTAssertEqual(events.last?.preferences, preferences)
        XCTAssertEqual(events.last?.locatorJson, middleJSON, "Relayout must retain the original content anchor")
        let visibleAfter = try await paragraphSixtyIsVisible(in: reader)
        XCTAssertTrue(visibleAfter, "Preserved locator must still be rendered in the actual viewport")
        let renderedNavigator = try XCTUnwrap(reader.children.compactMap { $0 as? EPUBNavigatorViewController }.first)
        let renderedColumns = try await renderedNavigator.evaluateJavaScript("getComputedStyle(document.documentElement).columnCount").get()
        XCTAssertEqual(renderedColumns as? String, reader.view.bounds.width >= 700 ? "2" : "1",
            "Validate actual CSS columns, including compact-window fallback")
        for theme in ["light", "dark", "sepia"] {
            let updated = ReaderPreferences(fontScale: 1.5, columnCount: 2, scroll: false, theme: theme)
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                do { try reader.apply(updated) { c.resume(with: $0) } }
                catch { c.resume(throwing: error) }
            }
            let palette = ReaderPalette.forTheme(theme)
            XCTAssertEqual(reader.view.backgroundColor, palette.background)
            XCTAssertEqual(navigation.navigationBar.standardAppearance.backgroundColor, palette.background)
            let active = try XCTUnwrap(reader.children.compactMap { $0 as? EPUBNavigatorViewController }.first)
            let background = try await active.evaluateJavaScript("getComputedStyle(document.documentElement).backgroundColor").get() as? String
            let packed = try XCTUnwrap(Color(uiColor: palette.background)).rawValue
            XCTAssertEqual(background, "rgb(\((packed >> 16) & 255), \((packed >> 8) & 255), \(packed & 255))")
            let bounds = active.view.bounds
            reader.navigator(active, didTapAt: CGPoint(x: bounds.midX, y: bounds.midY))
            reader.view.layoutIfNeeded()
            XCTAssertEqual(active.view.bounds, bounds, "Hiding chrome must not repaginate")
            reader.navigator(active, didTapAt: CGPoint(x: bounds.midX, y: bounds.midY))
            XCTAssertEqual(events.last?.locatorJson, middleJSON)
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        let snapshot = UIGraphicsImageRenderer(bounds: navigation.view.bounds).image { _ in
            navigation.view.drawHierarchy(in: navigation.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "Readium Korean paragraph after reflow"
        attachment.lifetime = .keepAlways
        add(attachment)
        let settingsButton = try XCTUnwrap(reader.navigationItem.rightBarButtonItems?.first {
            $0.accessibilityIdentifier == "reader.preferences"
        })
        XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(settingsButton.action),
            to: settingsButton.target, from: settingsButton, for: nil))
        try await Task.sleep(nanoseconds: 600_000_000)
        let settingsNavigation = try XCTUnwrap(reader.presentedViewController as? UINavigationController)
        let settings = try XCTUnwrap(settingsNavigation.topViewController as? ReaderSettingsViewController)
        settings.view.layoutIfNeeded()
        func segments(in view: UIView) -> [UISegmentedControl] {
            (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap { segments(in: $0) }
        }
        let themeControl = try XCTUnwrap(segments(in: settings.view).first { $0.tag == 1 })
        themeControl.selectedSegmentIndex = 2
        themeControl.sendActions(for: .valueChanged)
        for _ in 0..<100 {
            if settings.navigationItem.prompt == nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNil(settings.navigationItem.prompt)
        XCTAssertTrue(reader.presentedViewController === settingsNavigation, "Setting changes must keep the panel open")
        XCTAssertEqual(events.last?.preferences?.theme, "dark")
        XCTAssertEqual(events.last?.locatorJson, middleJSON)
        try await Task.sleep(nanoseconds: 400_000_000)
        let panelImage = UIGraphicsImageRenderer(bounds: navigation.view.bounds).image { _ in
            navigation.view.window?.drawHierarchy(in: navigation.view.bounds, afterScreenUpdates: true)
        }
        let panelAttachment = XCTAttachment(image: panelImage)
        panelAttachment.name = "Reading settings remain open in dark theme"
        panelAttachment.lifetime = .keepAlways
        add(panelAttachment)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            settingsNavigation.dismiss(animated: false) { c.resume() }
        }
        let locator = try Locator(jsonString: middleJSON)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do { try reader.go(to: locator) { continuation.resume(with: $0) } }
            catch { continuation.resume(throwing: error) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reader.close { continuation.resume(with: $0) }
        }
        XCTAssertEqual(events.last?.kind, "closed")
        XCTAssertNotNil(events.last?.locatorJson)
        XCTAssertEqual(events.map(\.sequence), events.map(\.sequence).sorted())
    }

    @MainActor
    func testCharacterAnchorSurvivesRepeatedReopenAndColumnChanges() async throws {
        let file = try await makeEPUB(longParagraph: true)
        let journal = try ReaderCheckpointStore(directory: directory.appendingPathComponent("repeat-journal"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let presenter = try XCTUnwrap(window.rootViewController)
        var events: [ReaderEvent] = []
        var generation: Int64 = 20
        func launch(_ locator: String?, _ preferences: ReaderPreferences) async throws -> KoofyReaderViewController {
            generation += 1
            let ready = expectation(description: "New session ready")
            let request = ReaderLaunchRequest(protocolVersion: 1, sessionId: "repeat-\(generation)",
                sessionGeneration: generation, publicationId: "repeat-fixture", contentRevision: "v1",
                filePath: file.path, title: "문자 위치 복원", initialLocatorJson: locator, preferences: preferences)
            let reader = KoofyReaderViewController(request: request, journal: journal) { event in
                events.append(event)
                if event.kind == "ready" { ready.fulfill() }
                if event.kind == "error" { XCTFail(event.message ?? "Reader error") }
            }
            let navigation = UINavigationController(rootViewController: reader)
            navigation.modalPresentationStyle = .fullScreen
            presenter.present(navigation, animated: false)
            await fulfillment(of: [ready], timeout: 35)
            return reader
        }
        var reader = try await launch(nil, ReaderPreferences(fontScale: 1, columnCount: 1, scroll: false, theme: "light"))
        let first = try Locator(jsonString: XCTUnwrap(events.last?.locatorJson))
        // Deliberately ambiguous quote: only the DOM point identifies the
        // requested character among repeated occurrences in the long paragraph.
        let middle = try Locator(jsonString: """
        {"href":"EPUB/chapter.xhtml","type":"application/xhtml+xml","locations":{"cssSelector":"#p60","koofyText":{"cssSelector":"#p60","textNodeIndex":0,"charOffset":2500}},"text":{"highlight":"문"}}
        """)
        XCTAssertEqual(first.href, middle.href)

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            do { try reader.go(to: middle) { c.resume(with: $0) } } catch { c.resume(throwing: error) }
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        let navigator = try XCTUnwrap(reader.children.compactMap { $0 as? EPUBNavigatorViewController }.first)
        let advanced = await navigator.goForward(options: .init(animated: false))
        XCTAssertTrue(advanced)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let canonical = try XCTUnwrap(events.last?.locatorJson)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(canonical.utf8)) as? [String: Any])
        let point = try XCTUnwrap((json["locations"] as? [String: Any])?["koofyText"] as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(point["charOffset"] as? Int), 0, "Must save inside the paragraph, not its start")
        for cycle in 0..<4 {
            let preferences = ReaderPreferences(fontScale: 1 + Double(cycle) * 0.1,
                columnCount: cycle % 2 == 0 ? 2 : 1, scroll: false, theme: "light")
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                do { try reader.apply(preferences) { c.resume(with: $0) } } catch { c.resume(throwing: error) }
            }
            try await Task.sleep(nanoseconds: 1_200_000_000)
            XCTAssertEqual(events.last?.locatorJson, canonical, "Reflow must preserve exact identity")
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                reader.close { c.resume(with: $0) }
            }
            let saved = try XCTUnwrap(journal.pending().first { $0.sessionId == "repeat-\(generation)" })
            XCTAssertEqual(saved.locatorJson, canonical)
            reader = try await launch(saved.locatorJson, try XCTUnwrap(saved.preferences))
            try await Task.sleep(nanoseconds: 1_200_000_000)
            XCTAssertEqual(events.last?.locatorJson, canonical, "Repeated reopening drifted backwards")
            let current = try XCTUnwrap(reader.children.compactMap { $0 as? EPUBNavigatorViewController }.first)
            let script = """
            (() => { const p = \(canonical).locations.koofyText;
              const n = document.querySelector(p.cssSelector).childNodes[p.textNodeIndex];
              const r = document.createRange(); r.setStart(n, p.charOffset); r.setEnd(n, p.charOffset + 1);
              return Array.from(r.getClientRects()).some(b => b.right > 0 && b.left < innerWidth && b.bottom > 0 && b.top < innerHeight);
            })()
            """
            let visible = try await current.evaluateJavaScript(script).get()
            XCTAssertEqual(visible as? Bool, true, "Canonical character must actually be on screen")
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            reader.close { c.resume(with: $0) }
        }
    }

    @MainActor
    private func paragraphSixtyIsVisible(in reader: KoofyReaderViewController) async throws -> Bool {
        let navigator = try XCTUnwrap(reader.children.compactMap { $0 as? EPUBNavigatorViewController }.first)
        let result = try await navigator.evaluateJavaScript("(() => { const e = document.getElementById('p60'); if (!e) return false; const r = e.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth; })()").get()
        return result as? Bool ?? false
    }

    private func makeEPUB(longParagraph: Bool = false) async throws -> URL {
        let file = directory.appendingPathComponent("reader-fixture.epub")
        let paragraphs = (1...120).map { index in
            let repeated = longParagraph && index == 60 ? (1...160).map { "긴 문단 \($0) 번째 문장입니다. 페이지와 문단의 시작은 다릅니다." }.joined(separator: " ") : ""
            return "<p id=\"p\(index)\">\(repeated)한글 문단 \(index). 책장을 넘기고 글자 크기를 바꾸어도 읽던 위치를 유지합니다. English text remains readable.</p>" }.joined()
        let entries = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<?xml version=\"1.0\"?><container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"EPUB/package.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>"),
            ("EPUB/package.opf", "<?xml version=\"1.0\"?><package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"id\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:identifier id=\"id\">koofy-render-test</dc:identifier><dc:title>한글 독서 검증</dc:title><dc:language>ko</dc:language><meta property=\"dcterms:modified\">2026-01-01T00:00:00Z</meta></metadata><manifest><item id=\"chapter\" href=\"chapter.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/></manifest><spine><itemref idref=\"chapter\"/></spine></package>"),
            ("EPUB/nav.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><head><title>목차</title></head><body><nav epub:type=\"toc\"><ol><li><a href=\"chapter.xhtml\">첫 장</a></li></ol></nav></body></html>"),
            ("EPUB/chapter.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"ko\"><head><title>첫 장</title></head><body>\(paragraphs)</body></html>"),
        ]
        let archive = try await Archive(url: file, accessMode: .create)
        for (path, text) in entries {
            let data = Data(text.utf8)
            try await archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<min(data.count, Int(position) + size))
            }
        }
        return file
    }

    private func event(sequence: Int64) -> ReaderEvent {
        ReaderEvent(protocolVersion: 1, sessionId: "session", sessionGeneration: 5,
            publicationId: "publication", contentRevision: "sha256:revision", sequence: sequence,
            kind: "locationChanged", locatorJson: "{\"href\":\"text/chapter.xhtml\",\"type\":\"application/xhtml+xml\",\"locations\":{\"cssSelector\":\"#p42\"}}",
            preferences: ReaderPreferences(fontScale: 1.4, columnCount: 2, scroll: false, theme: "sepia"))
    }
}
