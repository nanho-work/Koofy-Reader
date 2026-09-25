import AVFoundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Explicit device voice only. Never ask a network service or choose a language fallback.
private final class OfflineAppleSpeechEngine: TTSEngine, AVTTSEngineDelegate {
    private lazy var engine = AVTTSEngine(delegate: self)
    var voiceID: String?
    var speed: Double = 1
    var enabled = false
    var skipRemaining = 0
    var seeking = true
    var utteranceSequence = 0
    var availableVoices: [TTSVoice] {
        engine.availableVoices.filter { $0.language.code.bcp47.hasPrefix("ko") }
    }
    func speak(_ utterance: TTSUtterance, onSpeakRange: @escaping (Range<String.Index>) -> Void) async -> Result<Void, TTSError> {
        guard enabled, let id = voiceID,
              AVSpeechSynthesisVoice.speechVoices().contains(where: { $0.identifier == id }),
              availableVoices.contains(where: { $0.identifier == id }) else {
            return .failure(.other(NSError(domain: "KoofySpeech", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "선택한 로컬 음성을 사용할 수 없습니다."])))
        }
        if skipRemaining > 0 {
            await Task.yield()
            guard enabled, !Task.isCancelled else { return .failure(.other(CancellationError())) }
            skipRemaining -= 1
            return .success(())
        }
        seeking = false
        utteranceSequence += 1
        return await engine.speak(utterance, onSpeakRange: onSpeakRange)
    }
    func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
        // The selected installed voice is checked immediately before this synchronous callback.
        utterance.voice = voiceID.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
        utterance.postUtteranceDelay = 0.10
    }
}

/// The foreground controller owns activation for both previews and books. In particular,
/// queued Readium state callbacks must not reactivate audio after the reader has left.
private final class ForegroundSpeechAudioSession: AudioSessionManaging {
    func start(with user: AudioSessionUser, isPlaying: Bool) {}
    func end(for user: AudioSessionUser) {}
    func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool) {}
}

/// Owned by one reader controller; no background mode, microphone, remote controls or cloud API.
final class ReaderSpeech: NSObject, PublicationSpeechSynthesizerDelegate, AVSpeechSynthesizerDelegate {
    private let publication: Publication
    private let request: ReaderLaunchRequest
    private let visible: () async -> Locator?
    private let available: () -> Bool
    private let changed: () -> Void
    private let located: (Locator?) -> Void
    private let message: (String) -> Void
    private let defaults = UserDefaults.standard
    private let engine = OfflineAppleSpeechEngine()
    private let audioSession = ForegroundSpeechAudioSession()
    private var synthesizer: PublicationSpeechSynthesizer?
    private let previewSynth = AVSpeechSynthesizer()
    private var previewing = false
    private var startTask: Task<Void, Never>?
    private var timer: Timer?
    private var lastAudioSequence = -1
    private var utteranceMarker: String?
    private var utteranceOrdinal = -1
    private var utteranceStep = 1
    private var serial = 0
    private var active = true
    private var closed = false
    private var fromVisible = true
    private(set) var current: Locator?
    private(set) var playing = false
    private(set) var busy = false
    private(set) var used = false
    private(set) var voiceID: String?
    private(set) var speed: Double = 1
    private(set) var follow = true
    private(set) var timerMinutes = 0
    var voices: [TTSVoice] { engine.availableVoices }
    var hasSaved: Bool { saved() != nil }

    init(publication: Publication, request: ReaderLaunchRequest,
         visible: @escaping () async -> Locator?, available: @escaping () -> Bool,
         changed: @escaping () -> Void, located: @escaping (Locator?) -> Void,
         message: @escaping (String) -> Void) {
        self.publication = publication; self.request = request
        self.visible = visible; self.available = available; self.changed = changed
        self.located = located; self.message = message
        super.init()
        previewSynth.delegate = self
        voiceID = defaults.string(forKey: "reader.speech.voice")
        let rate = defaults.double(forKey: "reader.speech.speed")
        speed = rate.isFinite && rate >= 0.5 && rate <= 2 ? rate : 1
        follow = defaults.object(forKey: "reader.speech.follow") as? Bool ?? true
        if voiceID == nil { voiceID = voices.first?.identifier }
        engine.voiceID = voiceID; engine.speed = speed
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    deinit { timer?.invalidate(); startTask?.cancel(); NotificationCenter.default.removeObserver(self) }
    func foreground(_ value: Bool) { active = value; if !value { pause() } }
    func toggle() { if playing || busy { pause() } else { start() } }
    func start(savedPosition: Bool = false) {
        guard !closed, active, available() else { return }
        stopPreview()
        used = true; changed()
        guard let id = voiceID, voices.contains(where: { $0.identifier == id }) else {
            message("로컬 한국어 음성이 없습니다. iPhone 설정의 손쉬운 사용에서 읽기 및 말하기(또는 콘텐츠 말하기) → 음성 → 한국어 음성을 다운로드한 뒤 다시 열어 주세요.")
            return
        }
        used = true; busy = true; changed(); serial += 1
        let generation = serial
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let target: Locator?
            if savedPosition { target = self.saved() }
            else if self.fromVisible { target = await self.visible() }
            else { target = self.current }
            guard !Task.isCancelled, generation == self.serial, self.active, !self.closed else { return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                self.busy = false; self.changed(); self.message("다른 소리 재생이 끝난 뒤 다시 눌러 주세요."); return
            }
            let start: SpeechStart?
            do {
                if let target { start = try await speechStart(publication: self.publication, target: target) }
                else { start = nil }
            }
            catch {
                guard generation == self.serial, !Task.isCancelled else { return }
                self.pause(); self.message("읽던 문장을 찾지 못했습니다. 본문 위치를 옮긴 뒤 다시 재생해 주세요."); return
            }
            guard !Task.isCancelled, generation == self.serial, self.active, !self.closed else { return }
            self.engine.skipRemaining = start?.skip ?? 0
            self.utteranceOrdinal = (start?.skip ?? 0) - 1
            self.utteranceMarker = nil
            self.utteranceStep = 1
            self.lastAudioSequence = -1
            self.engine.seeking = true
            self.synthesizer?.stop()
            let synth = PublicationSpeechSynthesizer(publication: self.publication,
                config: .init(defaultLanguage: Language(code: .bcp47("ko")), voiceIdentifier: id),
                audioSession: self.audioSession,
                engineFactory: { [engine = self.engine] in engine }, delegate: self)
            guard let synth else { self.pause(); self.message("이 책의 읽을 본문을 준비하지 못했습니다."); return }
            self.synthesizer = synth
            self.engine.voiceID = id; self.engine.speed = self.speed; self.engine.enabled = true
            self.fromVisible = false; self.playing = true; self.changed()
            synth.start(from: start?.locator)
        }
    }
    func pause() {
        serial += 1; startTask?.cancel(); startTask = nil
        engine.enabled = false
        playing = false; busy = false
        synthesizer?.stop(); synthesizer = nil
        stopPreview(); save(); changed()
        let generation = serial
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, generation == self.serial, !self.playing, !self.previewing else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    func userNavigation() { pause(); fromVisible = true; located(nil) }
    func skip(_ forward: Bool) {
        guard playing, !busy, active, !closed else { return }
        utteranceStep = forward ? 1 : -1
        if forward { synthesizer?.next() } else { synthesizer?.previous() }
    }
    func selectVoice(_ id: String) {
        pause(); voiceID = id; engine.voiceID = id
        defaults.set(id, forKey: "reader.speech.voice")
    }
    func setSpeed(_ rate: Double) { pause(); speed = min(2, max(0.5, rate)); engine.speed = speed; defaults.set(speed, forKey: "reader.speech.speed") }
    func setFollow(_ value: Bool) { follow = value; defaults.set(value, forKey: "reader.speech.follow") }
    func setTimer(_ minutes: Int) {
        timer?.invalidate(); timerMinutes = minutes
        guard minutes > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            self?.timerMinutes = 0; self?.pause(); self?.message("설정한 시간이 되어 듣기를 멈췄습니다.")
        }
    }
    func preview() {
        pause()
        guard active, !closed, let id = voiceID, voices.contains(where: { $0.identifier == id }),
              let voice = AVSpeechSynthesisVoice(identifier: id) else { message("설치된 로컬 음성을 먼저 선택해 주세요."); return }
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio); try AVAudioSession.sharedInstance().setActive(true) }
        catch { message("음성 재생을 시작하지 못했습니다."); return }
        let utterance = AVSpeechUtterance(string: "안녕하세요. 쿠피리더에서 편안하게 책을 들어 보세요.")
        utterance.voice = voice; utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed))
        previewing = true
        previewSynth.speak(utterance)
    }
    func stopPreview() {
        guard previewing else { return }
        previewing = false
        previewSynth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { stopPreview() }
    func close() {
        guard !closed else { return }
        pause(); closed = true; timer?.invalidate(); synthesizer?.stop(); synthesizer = nil
        NotificationCenter.default.removeObserver(self)
    }
    @objc private func interrupted() { pause() }
    @objc private func routeChanged(_ notification: Notification) {
        if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
           AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { pause() }
    }
    @MainActor func publicationSpeechSynthesizer(_ synthesizer: PublicationSpeechSynthesizer, stateDidChange state: PublicationSpeechSynthesizer.State) {
        guard self.synthesizer === synthesizer, playing, active, !closed else { return }
        switch state {
        case let .playing(utterance, _):
            guard !engine.seeking else { return }
            busy = false; changed()
            guard lastAudioSequence != engine.utteranceSequence else { return }
            lastAudioSequence = engine.utteranceSequence
            let marker = "\(utterance.locator.href):\(utterance.locator.locations.otherLocations["cssSelector"] ?? .null)"
            if utteranceMarker == nil { utteranceOrdinal += 1 }
            else if utteranceMarker != marker { utteranceOrdinal = utteranceStep < 0 ? -1 : 0 }
            else if utteranceOrdinal >= 0 { utteranceOrdinal = max(0, utteranceOrdinal + utteranceStep) }
            utteranceMarker = marker; utteranceStep = 1
            var locator = utterance.locator
            if utteranceOrdinal >= 0 { locator.locations.otherLocations["koofySpeechOrdinal"] = .integer(utteranceOrdinal) }
            current = locator; save(); located(locator)
        case .stopped:
            pause()
            message("읽기가 끝났습니다.")
        case .paused: break
        }
    }
    @MainActor func publicationSpeechSynthesizer(_ synthesizer: PublicationSpeechSynthesizer,
        utterance: PublicationSpeechSynthesizer.Utterance, didFailWithError error: PublicationSpeechSynthesizer.Error) {
        guard self.synthesizer === synthesizer, playing, !closed else { return }
        pause(); message("음성을 재생하지 못했습니다. 기기의 한국어 음성 설치 상태를 확인해 주세요.")
    }
    private var positionKey: String { "reader.speech.position.\(request.publicationId)" }
    private func save() {
        guard let current, let json = try? current.jsonString() else { return }
        defaults.set(["revision": request.contentRevision, "locator": json], forKey: positionKey)
    }
    private func saved() -> Locator? {
        guard let data = defaults.dictionary(forKey: positionKey), data["revision"] as? String == request.contentRevision,
              let json = data["locator"] as? String, let locator = try? Locator(jsonString: json),
              publication.linkWithHREF(locator.href) != nil else { return nil }
        return locator
    }
}
