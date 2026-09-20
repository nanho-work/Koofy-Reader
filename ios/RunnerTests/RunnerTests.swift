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

    func testPageTurnStyleSurvivesJournalAndLegacyDefaults() throws {
        let journal = try ReaderCheckpointStore(directory: directory)
        var changed = event(sequence: 1)
        changed.preferences?.pageTurnStyle = "curl"
        changed.preferences?.fontId = "maplestory"
        try journal.write(changed)
        XCTAssertEqual(try journal.pending().first?.preferences?.pageTurnStyle, "curl")
        let path = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        XCTAssertEqual(try journal.pending().first?.preferences?.fontId, "maplestory")
        json.removeValue(forKey: "pageTurnStyle")
        json.removeValue(forKey: "fontId")
        try JSONSerialization.data(withJSONObject: json).write(to: path)
        XCTAssertNil(try journal.pending().first?.preferences?.pageTurnStyle)
        XCTAssertEqual(try journal.pending().first?.preferences?.fontId ?? "default", "default")
        XCTAssertEqual(try journal.pending().first?.locatorJson, changed.locatorJson)
    }

    func testDownloadedFontCatalogLoadsVerifiedFacesAndSkipsCorruptOnes() throws {
        let bundled = directory.appendingPathComponent("bundled")
        let remote = directory.appendingPathComponent("downloaded")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        _ = try ReaderFonts(directory: bundled, downloadedDirectory: remote)
        let source = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil).first)
        let target = remote.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: target)
        let id = "remote_" + String(repeating: "a", count: 32)
        let json: [String: Any] = ["version": 1, "families": [["id": id, "label": "다운로드 글꼴", "cssFamily": "KoofyRemote_" + String(repeating: "a", count: 32), "faces": [["file": target.lastPathComponent, "weight": 400, "sha256": target.deletingPathExtension().lastPathComponent]]]]]
        try JSONSerialization.data(withJSONObject: json).write(to: remote.appendingPathComponent("catalog.json"))
        let loaded = try ReaderFonts(directory: bundled, downloadedDirectory: remote)
        XCTAssertTrue(loaded.optionIds.contains(id))
        XCTAssertEqual(loaded.optionLabels.last, "다운로드 글꼴")
        XCTAssertNotNil(loaded.family(id))
        try Data("corrupted downloaded font".utf8).write(to: target)
        let repaired = try ReaderFonts(directory: bundled, downloadedDirectory: remote)
        XCTAssertFalse(repaired.optionIds.contains(id))
        XCTAssertTrue(repaired.optionIds.contains("maplestory"))
        XCTAssertTrue(ReaderFonts.isValidId(id))
        XCTAssertFalse(ReaderFonts.isValidId("remote_../escape"))
    }

    func testCorruptLocalFontIsRepairedFromBundle() throws {
        let fonts = directory.appendingPathComponent("fonts")
        _ = try ReaderFonts(directory: fonts)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: file)
        try Data("interrupted download".utf8).write(to: file)
        _ = try ReaderFonts(directory: fonts)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor
    func testLocalFontFacesReflowRestoreAndCurl() async throws {
        let file = try await makeEPUB(fontFaces: true)
        let journal = try ReaderCheckpointStore(directory: directory.appendingPathComponent("journal"))
        var events: [ReaderEvent] = []
        let ready = expectation(description: "Custom font reader ready")
        var preferences = ReaderPreferences(fontScale: 1, columnCount: 1, scroll: false,
            theme: "sepia", pageTurnStyle: "curl", fontId: "maplestory")
        let reader = KoofyReaderViewController(request: ReaderLaunchRequest(protocolVersion: 1,
            sessionId: "fonts", sessionGeneration: 100, publicationId: "font-fixture", contentRevision: "1",
            filePath: file.path, title: "글꼴 검증", initialLocatorJson: "{\"href\":\"EPUB/chapter.xhtml\",\"type\":\"application/xhtml+xml\",\"locations\":{\"fragments\":[\"p60\"]}}",
            preferences: preferences), journal: journal) { event in
                events.append(event)
                if event.kind == "ready" { ready.fulfill() }
                if event.kind == "error" { XCTFail(event.message ?? "Reader error") }
            }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let presenter = try XCTUnwrap(scene.windows.first { $0.isKeyWindow }?.rootViewController)
        let navigation = UINavigationController(rootViewController: reader)
        navigation.modalPresentationStyle = .fullScreen
        presenter.present(navigation, animated: false)
        defer { navigation.dismiss(animated: false) }
        await fulfillment(of: [ready], timeout: 35)
        let original = try XCTUnwrap(events.last?.locatorJson)
        func active() throws -> EPUBNavigatorViewController {
            try XCTUnwrap(reader.children.compactMap { $0 as? EPUBNavigatorViewController }.first)
        }
        let maple = try active()
        let family = try await maple.evaluateJavaScript("getComputedStyle(document.querySelector('p')).fontFamily").get() as? String
        XCTAssertTrue(family?.contains("KoofyMaplestory") == true)
        let loaded = try await maple.evaluateJavaScript("Array.from(document.fonts).filter(f=>f.family.includes('KoofyMaplestory')&&f.status==='loaded').map(f=>f.weight).sort().join(',')").get() as? String
        XCTAssertEqual(loaded, "300,700", "Regular must load Light and strong must load the real Bold OTF")
        let strongWeight = try await maple.evaluateJavaScript("getComputedStyle(document.querySelector('strong')).fontWeight").get() as? String
        XCTAssertEqual(strongWeight, "700")
        let before = try await waitForCurl(in: reader)
        let generation = before.frames.current.generation
        preferences.fontId = "hakgyoansim-siganpyo"
        // Font-only change must relayout and invalidate both main and preview.
        try await applyForCurlTest(preferences, to: reader)
        let school = try active()
        XCTAssertFalse(maple === school)
        let schoolFamily = try await school.evaluateJavaScript("getComputedStyle(document.querySelector('p')).fontFamily").get() as? String
        XCTAssertTrue(schoolFamily?.contains("KoofySiganpyo") == true)
        let schoolLoaded = try await school.evaluateJavaScript("Array.from(document.fonts).some(f=>f.family.includes('KoofySiganpyo')&&f.weight==='400'&&f.status==='loaded')").get() as? Bool
        XCTAssertEqual(schoolLoaded, true)
        let after = try await waitForCurl(in: reader)
        XCTAssertNotEqual(generation, after.frames.current.generation)
        XCTAssertEqual(events.last?.locatorJson, original)
        let visible = try await paragraphSixtyIsVisible(in: reader)
        XCTAssertTrue(visible)
        let attachment = XCTAttachment(image: after.frames.current.image)
        attachment.name = "학교안심 시간표 본문"
        attachment.lifetime = .keepAlways
        add(attachment)
        let target = try XCTUnwrap(after.frames.next?.locator.jsonString())
        XCTAssertTrue(after.turn(forward: true))
        for _ in 0..<150 {
            if events.last?.locatorJson == target { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(events.last?.locatorJson, target)
        preferences.fontScale = 1.4
        preferences.columnCount = 2
        try await applyForCurlTest(preferences, to: reader)
        XCTAssertEqual(events.last?.locatorJson, target)
        let spread = try await waitForCurl(in: reader)
        XCTAssertEqual(spread.frames.current.columns, reader.view.bounds.width >= 700 ? 2 : 1)
        preferences.scroll = true
        try await applyForCurlTest(preferences, to: reader)
        XCTAssertEqual(events.last?.locatorJson, target)
        preferences.fontId = "default"
        try await applyForCurlTest(preferences, to: reader)
        let defaultFamily = try await active().evaluateJavaScript("getComputedStyle(document.querySelector('p')).fontFamily").get() as? String
        XCTAssertFalse(defaultFamily?.contains("Koofy") == true)
        XCTAssertEqual(events.last?.locatorJson, target)
        XCTAssertEqual(try journal.pending().last?.preferences?.fontId, "default")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            reader.close { c.resume(with: $0) }
        }
    }

    @MainActor
    func testPageFramesCurlCommitCancellationAndStyleOnlyUpdate() async {
        do { try await verifyPageFramesAndCurl() }
        catch { XCTFail("Page curl scenario failed: \(error)") }
    }

    @MainActor
    func testSinglePageCurlMatchesNativeTurnAcrossChapterBoundary() async {
        do { try await verifyPageFramesAndCurl(startingColumns: 1, chapterBoundary: true) }
        catch { XCTFail("Single/chapter curl scenario failed: \(error)") }
    }

    @MainActor
    func testInteractiveCurlGestureProbe() async throws {
        guard ProcessInfo.processInfo.environment["KOOFY_INTERACTIVE_CURL"] == "1" else {
            throw XCTSkip("Run with TEST_RUNNER_KOOFY_INTERACTIVE_CURL=1 for Simulator touch injection")
        }
        let columns: Int64 = ProcessInfo.processInfo.environment["KOOFY_INTERACTIVE_CURL_COLUMNS"] == "1" ? 1 : 2
        do { try await verifyPageFramesAndCurl(manualProbe: true, startingColumns: columns) }
        catch { XCTFail("Interactive page curl failed: \(error)") }
    }

    @MainActor
    private func verifyPageFramesAndCurl(manualProbe: Bool = false, startingColumns: Int64 = 2,
                                        chapterBoundary: Bool = false) async throws {
        let file = try await makeEPUB(longParagraph: true, chapterBoundary: chapterBoundary)
        let journal = try ReaderCheckpointStore(directory: directory.appendingPathComponent("curl-journal"))
        var events: [ReaderEvent] = []
        let ready = expectation(description: "Curl reader ready")
        let preferences = ReaderPreferences(fontScale: 1, columnCount: startingColumns, scroll: false,
            theme: "sepia", pageTurnStyle: "curl")
        let reader = KoofyReaderViewController(request: ReaderLaunchRequest(protocolVersion: 1,
            sessionId: "curl", sessionGeneration: 99, publicationId: "curl-fixture", contentRevision: "1",
            filePath: file.path, title: "페이지 컬 검증", preferences: preferences), journal: journal) { event in
                events.append(event)
                if event.kind == "ready" { ready.fulfill() }
                if event.kind == "error" { XCTFail(event.message ?? "Reader error") }
            }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let presenter = try XCTUnwrap(window.rootViewController)
        let navigation = UINavigationController(rootViewController: reader)
        navigation.modalPresentationStyle = .fullScreen
        presenter.present(navigation, animated: false)
        defer { navigation.dismiss(animated: false) }
        await fulfillment(of: [ready], timeout: 35)
        let active = try XCTUnwrap(reader.children.compactMap { $0 as? EPUBNavigatorViewController }.first)
        let original = try XCTUnwrap(events.last?.locatorJson)
        var baseline: Locator?
        if !manualProbe {
            let moved = await active.goForward(options: .init(animated: false))
            XCTAssertTrue(moved)
            try await ReaderWebViewport.waitUntilStable(active)
            baseline = try await ReaderWebViewport.exactLocator(in: active)
            if chapterBoundary { XCTAssertNotEqual(baseline?.href, try Locator(jsonString: original).href) }
            let source = try Locator(jsonString: original)
            let result: Result<Void, Error> = await withCheckedContinuation { continuation in
                do { try reader.go(to: source) { continuation.resume(returning: $0) } }
                catch { continuation.resume(returning: .failure(error)) }
            }
            try result.get()
        }
        let before = try journal.pending()
        let started = Date()
        let controller = try await waitForCurl(in: reader)
        let frames = controller.frames
        print("KOOFY_FRAME_CAPTURE seconds=\(Date().timeIntervalSince(started)) width=\(frames.current.image.cgImage?.width ?? 0) height=\(frames.current.image.cgImage?.height ?? 0) columns=\(frames.current.columns)")
        XCTAssertEqual(frames.current.columns, startingColumns != 1 && reader.view.bounds.width >= 700 ? 2 : 1)
        XCTAssertEqual(events.last?.locatorJson, original)
        XCTAssertEqual(try journal.pending(), before, "Preview must not write a checkpoint")
        let next = try XCTUnwrap(frames.next)
        XCTAssertNotNil(next.locator.locations.position)
        XCTAssertNotNil(next.locator.locations.totalProgression, "Curl targets must retain library/footer reading progress")
        XCTAssertGreaterThan(next.locator.locations.totalProgression ?? 0, frames.current.locator.locations.totalProgression ?? 0)
        let pageController = try XCTUnwrap(controller.children.compactMap { $0 as? UIPageViewController }.first)
        XCTAssertTrue(pageController.isDoubleSided)
        if startingColumns == 1 {
            let front = try XCTUnwrap(pageController.viewControllers?.first)
            let back = try XCTUnwrap(frames.rightToLeft
                ? controller.pageViewController(pageController, viewControllerBefore: front)
                : controller.pageViewController(pageController, viewControllerAfter: front))
            let destination = try XCTUnwrap(frames.rightToLeft
                ? controller.pageViewController(pageController, viewControllerBefore: back)
                : controller.pageViewController(pageController, viewControllerAfter: back))
            func images(in view: UIView) -> [UIImageView] {
                (view as? UIImageView).map { [$0] } ?? view.subviews.flatMap { images(in: $0) }
            }
            XCTAssertTrue(images(in: back.view).first?.image === next.image,
                "The reverse side must carry real destination text")
            XCTAssertTrue(images(in: destination.view).first?.image === next.image,
                "The next visible face must advance one viewport")
        }
        if let baseline {
            XCTAssertEqual(next.locator.href, baseline.href)
            let expected = try JSONSerialization.jsonObject(with: Data(baseline.jsonString().utf8)) as? [String: Any]
            let prepared = try JSONSerialization.jsonObject(with: Data(next.locator.jsonString().utf8)) as? [String: Any]
            let expectedPoint = (expected?["locations"] as? [String: Any])?["koofyText"] as? [String: Any] ?? [:]
            let preparedPoint = (prepared?["locations"] as? [String: Any])?["koofyText"] as? [String: Any] ?? [:]
            XCTAssertEqual(NSDictionary(dictionary: expectedPoint), NSDictionary(dictionary: preparedPoint),
                "Prepared destination must match one independent Readium goForward(false), including character offset")
        }
        XCTAssertNotEqual(try next.locator.jsonString(), try frames.current.locator.jsonString())
        let pixels = try XCTUnwrap(frames.current.image.cgImage?.dataProvider?.data) as Data
        XCTAssertGreaterThan(Set(pixels).count, 40, "Captured EPUB needs real antialiased glyphs, not a blank surface")
        let attachment = XCTAttachment(image: frames.current.image)
        attachment.name = "Real EPUB current viewport for curl"
        attachment.lifetime = .keepAlways
        add(attachment)
        let nextAttachment = XCTAttachment(image: next.image)
        nextAttachment.name = "Independent preview next viewport for curl"
        nextAttachment.lifetime = .keepAlways
        add(nextAttachment)

        if manualProbe {
            print("KOOFY_GESTURE_READY original=\(original)")
            let requireCancel = ProcessInfo.processInfo.environment["KOOFY_INTERACTIVE_CURL_REQUIRE_CANCEL"] == "1"
            var observedCancellation = false
            var observedCommit = false
            weak var hookedController: ReaderPageTurnController?
            for _ in 0..<6000 {
                if let activeCurl = reader.children.compactMap({ $0 as? ReaderPageTurnController }).first,
                   hookedController !== activeCurl {
                    hookedController = activeCurl
                    let priorCancel = activeCurl.onCancel
                    let cancelSource = try journal.pending()
                    activeCurl.onCancel = {
                        priorCancel?()
                        let unchanged = (try? journal.pending()) == cancelSource
                        print("KOOFY_GESTURE_CANCELLED journalUnchanged=\(unchanged)")
                        XCTAssertTrue(unchanged)
                        observedCancellation = true
                    }
                }
                if !observedCommit, events.last?.locatorJson != original {
                    print("KOOFY_GESTURE_COMMITTED exactTarget=\(events.last?.locatorJson == (try next.locator.jsonString()))")
                    XCTAssertEqual(events.last?.locatorJson, try next.locator.jsonString())
                    observedCommit = true
                }
                if observedCommit && (!requireCancel || observedCancellation) { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            if requireCancel { XCTAssertTrue(observedCancellation, "Actual UIKit edge drag must be cancelled once") }
            XCTAssertTrue(observedCommit)
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                reader.close { c.resume(with: $0) }
            }
            return
        }

        // Exercise UIKit's begin/end-without-completion delegate sequence,
        // including the host's busy state, without pretending to inject touch.
        controller.pageViewController(pageController,
            willTransitionTo: pageController.viewControllers ?? [])
        XCTAssertTrue(controller.isTurning)
        controller.pageViewController(pageController, didFinishAnimating: true,
            previousViewControllers: pageController.viewControllers ?? [], transitionCompleted: false)
        XCTAssertFalse(controller.isTurning)
        print("KOOFY_STAGE cancelled")
        XCTAssertEqual(events.last?.locatorJson, original)
        XCTAssertEqual(try journal.pending(), before)
        XCTAssertTrue(controller.turn(forward: true))
        print("KOOFY_STAGE animation started")
        for _ in 0..<150 {
            if events.last?.locatorJson != original { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let committed = try XCTUnwrap(events.last?.locatorJson)
        print("KOOFY_STAGE committed")
        XCTAssertNotEqual(committed, original)
        XCTAssertEqual(committed, try next.locator.jsonString(), "Commit must use the exact prepared character")
        let actual = try await ReaderWebViewport.exactLocator(in: active)
        XCTAssertEqual(actual.text.highlight, next.locator.text.highlight)
        let nextLocation = try JSONSerialization.jsonObject(with: Data(next.locator.jsonString().utf8)) as? [String: Any]
        let actualLocation = try JSONSerialization.jsonObject(with: Data(actual.jsonString().utf8)) as? [String: Any]
        XCTAssertEqual(NSDictionary(dictionary: nextLocation?["locations"] as? [String: Any] ?? [:]),
            NSDictionary(dictionary: actualLocation?["locations"] as? [String: Any] ?? [:]))
        print("KOOFY_STAGE exact target checked")

        var instant = preferences
        instant.pageTurnStyle = "instant"
        try await applyForCurlTest(instant, to: reader)
        XCTAssertTrue(reader.children.contains { $0 === active }, "Changing only the effect must retain navigator identity")
        XCTAssertEqual(events.last?.locatorJson, committed)
        XCTAssertTrue(reader.children.compactMap { $0 as? ReaderPageTurnController }.isEmpty)
        print("KOOFY_STAGE instant style checked")

        var larger = preferences
        larger.fontScale = 1.4
        larger.columnCount = 1
        print("KOOFY_STAGE applying larger font")
        try await applyForCurlTest(larger, to: reader)
        print("KOOFY_STAGE larger font applied")
        let refreshed = try await waitForCurl(in: reader)
        print("KOOFY_STAGE font refreshed")
        print("KOOFY_SINGLE_DOUBLE_SIDED \(refreshed.children.compactMap { $0 as? UIPageViewController }.first?.isDoubleSided == true)")
        XCTAssertEqual(refreshed.children.compactMap { $0 as? UIPageViewController }.first?.isDoubleSided, true)
        XCTAssertNotEqual(refreshed.frames.current.generation, frames.current.generation)
        XCTAssertEqual(refreshed.frames.current.columns, 1)
        XCTAssertEqual(events.last?.locatorJson, committed, "Font/column invalidation must preserve resume identity")
        let singleSource = try refreshed.frames.current.locator.jsonString()
        let singleTarget = try XCTUnwrap(refreshed.frames.next)
        XCTAssertTrue(refreshed.turn(forward: true))
        for _ in 0..<100 {
            if events.last?.locatorJson == (try singleTarget.locator.jsonString()) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(events.last?.locatorJson, try singleTarget.locator.jsonString(), "Single curl advances only one viewport")
        let reverse = try await waitForCurl(in: reader)
        XCTAssertTrue(reverse.turn(forward: false))
        for _ in 0..<100 {
            if events.last?.locatorJson == singleSource { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(events.last?.locatorJson, singleSource, "Single reverse must return to the source viewport")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            reader.close { c.resume(with: $0) }
        }
    }

    @MainActor
    private func waitForCurl(in reader: KoofyReaderViewController) async throws -> ReaderPageTurnController {
        for _ in 0..<200 {
            if let controller = reader.children.compactMap({ $0 as? ReaderPageTurnController }).first { return controller }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "PageCurl", code: 1, userInfo: [NSLocalizedDescriptionKey: "Actual EPUB frame preparation failed"])
    }

    @MainActor
    private func applyForCurlTest(_ preferences: ReaderPreferences, to reader: KoofyReaderViewController) async throws {
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            do { try reader.apply(preferences) { continuation.resume(returning: $0) } }
            catch { continuation.resume(returning: .failure(error)) }
        }
        try result.get()
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
        let themeControl = try XCTUnwrap(segments(in: settings.view).first { $0.tag == 2 })
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

    private func makeEPUB(longParagraph: Bool = false, chapterBoundary: Bool = false, fontFaces: Bool = false) async throws -> URL {
        let file = directory.appendingPathComponent("reader-fixture.epub")
        let paragraphs = (1...120).map { index in
            let bold = fontFaces ? "<strong>굵은 글씨 Bold</strong>" : ""
            let repeated = longParagraph && index == 60 ? (1...160).map { "긴 문단 \($0) 번째 문장입니다. 페이지와 문단의 시작은 다릅니다." }.joined(separator: " ") : ""
            return "<p id=\"p\(index)\">\(repeated)한글 문단 \(index). 책장을 넘기고 글자 크기를 바꾸어도 읽던 위치를 유지합니다. English text remains readable.\(bold)</p>" }.joined()
        var entries = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<?xml version=\"1.0\"?><container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"EPUB/package.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>"),
            ("EPUB/package.opf", "<?xml version=\"1.0\"?><package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"id\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:identifier id=\"id\">koofy-render-test</dc:identifier><dc:title>한글 독서 검증</dc:title><dc:language>ko</dc:language><meta property=\"dcterms:modified\">2026-01-01T00:00:00Z</meta></metadata><manifest><item id=\"chapter\" href=\"chapter.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/></manifest><spine><itemref idref=\"chapter\"/></spine></package>"),
            ("EPUB/nav.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><head><title>목차</title></head><body><nav epub:type=\"toc\"><ol><li><a href=\"chapter.xhtml\">첫 장</a></li></ol></nav></body></html>"),
            ("EPUB/chapter.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"ko\"><head><title>첫 장</title></head><body>\(paragraphs)</body></html>"),
        ]
        if chapterBoundary {
            entries = entries.map { path, text in
                if path == "EPUB/package.opf" {
                    return (path, text.replacingOccurrences(of: "</manifest>", with: "<item id=\"second\" href=\"second.xhtml\" media-type=\"application/xhtml+xml\"/></manifest>")
                        .replacingOccurrences(of: "</spine>", with: "<itemref idref=\"second\"/></spine>"))
                }
                if path == "EPUB/chapter.xhtml" {
                    return (path, "<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"ko\"><head><title>첫 장</title></head><body><p id=\"p1\">짧은 첫 장. 다음 책장을 넘기면 새로운 장으로 이동합니다.</p></body></html>")
                }
                return (path, text)
            }
            entries.append(("EPUB/second.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"ko\"><head><title>두 번째 장</title></head><body>\(paragraphs)</body></html>"))
        }
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
