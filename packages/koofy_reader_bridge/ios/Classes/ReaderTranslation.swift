import UIKit
import AVFoundation
import MLKitTranslate
import MLKitCommon

/// Session-only learning aid, with no writes to reading/TTS checkpoints.
@MainActor
final class ReaderTranslation {
    let view = UIStackView()
    private(set) var enabled = false
    var sample: ((String) async -> String?)?
    var pauseBook: (() -> Void)?
    var onClose: (() -> Void)?
    private let text = UILabel()
    private let scroll = UIScrollView()
    private let prepareButton = UIButton(type: .system)
    private let originalButton = UIButton(type: .system)
    private let translatedButton = UIButton(type: .system)
    private let badge = UIImageView()
    private let heading = UILabel()
    private let closeButton = UIButton(type: .system)
    private var translator: Translator?
    private var task: Task<Void, Never>?
    private var preparationTimeout: Task<Void, Never>?
    private var generation = 0
    private var modelGeneration = 0
    private var foreground = true
    private var ready = false
    private var downloading = false
    private var pending = ""
    private var identity = ""
    private var changedAt = Date.distantPast
    private var source = ""
    private var translated = ""
    private let synthesizer = AVSpeechSynthesizer()
    private let resources: Bundle?
    private let script: String
    private var observers: [NSObjectProtocol] = []

    init() {
        resources = Bundle(for: ReaderTranslation.self).url(forResource: "KoofyReaderAssets", withExtension: "bundle").flatMap(Bundle.init(url:))
        script = resources?.url(forResource: "reader_selection", withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "null"
        view.axis = .vertical; view.isHidden = true; view.clipsToBounds = true
        view.isLayoutMarginsRelativeArrangement = true; view.directionalLayoutMargins = .init(top: 0, leading: 12, bottom: 2, trailing: 12)
        heading.text = "영어 → 한국어 · 번역"; heading.font = .preferredFont(forTextStyle: .caption1)
        closeButton.setTitle("끄기", for: .normal); closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let header = UIStackView(arrangedSubviews: [heading, closeButton]); let headerHeight = header.heightAnchor.constraint(equalToConstant: 40); headerHeight.priority = .init(999); headerHeight.isActive = true
        view.addArrangedSubview(header)
        text.numberOfLines = 0; text.font = .preferredFont(forTextStyle: .body); text.adjustsFontForContentSizeCategory = true
        text.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(text)
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), text.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), text.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), text.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), text.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        view.addArrangedSubview(scroll)
        originalButton.setTitle("원문 듣기", for: .normal); originalButton.addTarget(self, action: #selector(speakOriginal), for: .touchUpInside)
        translatedButton.setTitle("번역 듣기", for: .normal); translatedButton.addTarget(self, action: #selector(speakTranslation), for: .touchUpInside)
        prepareButton.addTarget(self, action: #selector(prepare), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [originalButton, translatedButton, prepareButton]); actions.distribution = .fillEqually
        let actionsHeight = actions.heightAnchor.constraint(equalToConstant: 44); actionsHeight.priority = .init(999); actionsHeight.isActive = true
        for button in [originalButton, translatedButton, prepareButton] { button.titleLabel?.font = .systemFont(ofSize: 12); button.titleLabel?.adjustsFontSizeToFitWidth = true }
        view.addArrangedSubview(actions)
        badge.contentMode = .scaleAspectFit; badge.accessibilityLabel = "powered by Google Translate"; badge.isAccessibilityElement = true
        let badgeHeight = badge.heightAnchor.constraint(equalToConstant: 22); badgeHeight.priority = .init(999); badgeHeight.isActive = true
        view.addArrangedSubview(badge)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.stopVoice() } })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.stopVoice() } }
        })
    }
    deinit { task?.cancel(); preparationTimeout?.cancel(); for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    func palette(_ palette: ReaderPalette) {
        view.backgroundColor = palette.background; text.textColor = palette.foreground; heading.textColor = palette.foreground
        for button in [originalButton, translatedButton, prepareButton, closeButton] { button.tintColor = palette.accent }
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1
        palette.background.getRed(&r, green: &g, blue: &b, alpha: nil)
        let name = (r + g + b) / 3 < 0.3 ? "translate-white-regular" : "translate-color-regular"
        badge.image = resources?.url(forResource: name, withExtension: "png").flatMap { UIImage(contentsOfFile: $0.path) }
    }
    func enable() {
        enabled = true; view.isHidden = false
        translator = Translator.translator(options: TranslatorOptions(sourceLanguage: .english, targetLanguage: .korean))
        ready = ModelManager.modelManager().downloadedTranslateModels.contains { $0.language == .korean }
        text.text = "단어를 길게 누르고 선택 범위를 조절하세요. 처음에는 Wi-Fi에서 번역 데이터를 준비합니다."
        controls(); resume()
    }
    private func controls() {
        originalButton.isEnabled = !source.isEmpty; translatedButton.isEnabled = !translated.isEmpty
        prepareButton.setTitle(downloading ? "준비 중…" : ready ? "다시 번역" : "번역 준비 · Wi-Fi", for: .normal)
        prepareButton.isEnabled = !downloading
    }
    @objc private func prepare() {
        if ready { identity = ""; return }
        guard let translator else { return }
        downloading = true; controls(); text.text = "Wi-Fi에서 번역 데이터를 준비하고 있습니다. 끄기를 눌러 독서를 계속할 수 있습니다."
        modelGeneration += 1; let token = modelGeneration
        preparationTimeout?.cancel()
        preparationTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
            guard let self, self.enabled, self.downloading, token == self.modelGeneration else { return }
            self.modelGeneration += 1; self.downloading = false
            self.text.text = "번역 준비가 지연되고 있습니다. Wi-Fi 연결을 확인하고 다시 시도하세요."
            self.controls()
        }
        translator.downloadModelIfNeeded(with: ModelDownloadConditions(allowsCellularAccess: false, allowsBackgroundDownloading: false)) { [weak self] error in
            Task { @MainActor in
                guard let self, self.enabled, token == self.modelGeneration else { return }
                self.preparationTimeout?.cancel()
                self.downloading = false; self.ready = error == nil; self.identity = ""
                self.text.text = error == nil ? "준비됐습니다. 단어나 문장을 길게 눌러 선택하세요." : "번역 데이터를 준비하지 못했습니다. Wi-Fi 연결을 확인하고 다시 시도하세요."
                self.controls()
            }
        }
    }
    func resume() {
        foreground = true
        guard enabled, task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard await self?.pollOnce() == true else { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }
    private func pollOnce() async -> Bool {
        guard enabled, foreground else { return false }
        if let raw = await sample?(script), let data = raw.data(using: .utf8),
           let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any], !Task.isCancelled {
            accept(snapshot)
        }
        return true
    }
    func accept(_ snapshot: [String: Any]) {
        guard enabled, foreground else { return }
        let value = (snapshot["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (snapshot["resource"] as? String ?? "") + "\n" + value
        if key != pending {
            pending = key; identity = ""; changedAt = Date(); generation += 1; stopVoice(); source = value; translated = ""; controls()
            if value.isEmpty { text.text = "단어나 문장을 길게 눌러 선택하세요." }
            else { pauseBook?(); text.text = value.utf16.count > 2000 ? "한 번에 2,000자까지 선택해 주세요." : "\(value)\n\n선택을 마치면 번역합니다." }
        }
        guard !value.isEmpty, value.utf16.count <= 2000, snapshot["busy"] as? Bool != true,
              key != identity, Date().timeIntervalSince(changedAt) >= 0.5 else { return }
        guard ready else { if !downloading { text.text = "\(value)\n\n번역 준비를 눌러 언어 데이터를 내려받으세요." }; return }
        identity = key; generation += 1; let token = generation
        text.text = "\(value)\n\n번역 중…"
        translator?.translate(value) { [weak self] output, error in
            Task { @MainActor in
                guard let self, self.enabled, self.foreground, token == self.generation else { return }
                self.translated = error == nil ? output ?? "" : ""
                self.text.text = "\(value)\n\n" + (self.translated.isEmpty ? "번역하지 못했습니다. 다시 번역을 눌러 주세요." : self.translated)
                self.controls()
            }
        }
    }
    private func speak(_ text: String, language: String) {
        guard !text.isEmpty, text.utf16.count <= 8000, foreground else { return }
        pauseBook?(); stopVoice()
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix(language) }) else {
            self.text.text = "기기 설정 → 손쉬운 사용 → 읽기 및 말하기에서 \(language == "en" ? "영어" : "한국어") 음성을 설치해 주세요."; return
        }
        let utterance = AVSpeechUtterance(string: text); utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
    @objc private func speakOriginal() { speak(source, language: "en") }
    @objc private func speakTranslation() { speak(translated, language: "ko") }
    @objc private func closeTapped() { onClose?() }
    func stopVoice() { synthesizer.stopSpeaking(at: .immediate) }
    func suspend() { foreground = false; generation += 1; identity = ""; task?.cancel(); task = nil; stopVoice() }
    func disable() { preparationTimeout?.cancel(); enabled = false; suspend(); modelGeneration += 1; translator = nil; downloading = false; source = ""; translated = ""; pending = ""; view.isHidden = true }
}
