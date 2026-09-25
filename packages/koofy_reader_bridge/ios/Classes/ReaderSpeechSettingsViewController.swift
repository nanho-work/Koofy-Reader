import UIKit

final class ReaderSpeechSettingsViewController: UITableViewController {
    private let speech: ReaderSpeech
    private let palette: ReaderPalette
    init(speech: ReaderSpeech, palette: ReaderPalette) {
        self.speech = speech; self.palette = palette
        super.init(style: .insetGrouped)
        title = "듣기 설정"
    }
    required init?(coder: NSCoder) { fatalError("Use init(speech:palette:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = palette.background
        tableView.tintColor = palette.accent
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "완료", style: .done, target: self, action: #selector(done))
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); speech.stopPreview() }
    @objc private func done() { dismiss(animated: true) }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return max(1, speech.voices.count); case 1: return 2; case 2: return 2; default: return speech.hasSaved ? 1 : 0 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["기기의 한국어 음성", "목소리와 속도", "재생 설정", "이어 듣기"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "음성 추가: iPhone 설정 → 손쉬운 사용 → 읽기 및 말하기(또는 콘텐츠 말하기) → 음성 → 한국어에서 다운로드하세요. 다운로드 후 독서 화면을 다시 열어 주세요."
        case 2: return "앱·독서 화면을 벗어나거나 화면을 잠그면 멈춥니다. 돌아와도 자동으로 재생하지 않습니다. 직접 페이지를 이동하면 새 위치에서 읽습니다."
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = palette.panel; cell.textLabel?.textColor = palette.foreground
        cell.detailTextLabel?.textColor = palette.secondary
        cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        switch path.section {
        case 0:
            if speech.voices.isEmpty { cell.textLabel?.text = "설치된 한국어 음성이 없습니다."; cell.selectionStyle = .none }
            else {
                let voice = speech.voices[path.row]
                cell.textLabel?.text = voice.name
                cell.detailTextLabel?.text = voice.language.code.bcp47
                cell.accessoryType = voice.identifier == speech.voiceID ? .checkmark : .none
            }
        case 1: cell.textLabel?.text = path.row == 0 ? "선택한 음성 미리 듣기" : "읽기 속도 · \(speech.speed)배"
        case 2:
            cell.textLabel?.text = path.row == 0 ? "음성을 따라 페이지 이동" : "취침 타이머 · \(speech.timerMinutes == 0 ? "사용 안 함" : "\(speech.timerMinutes)분")"
            if path.row == 0 { cell.accessoryType = speech.follow ? .checkmark : .none }
        default: cell.textLabel?.text = "저장된 듣던 위치부터 재생"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        switch path.section {
        case 0: if !speech.voices.isEmpty { speech.selectVoice(speech.voices[path.row].identifier) }
        case 1:
            if path.row == 0 { speech.preview() }
            else { choose(title: "읽기 속도", labels: ["0.75배", "1배", "1.25배", "1.5배", "2배"]) { [weak self] index in self?.speech.setSpeed([0.75, 1, 1.25, 1.5, 2][index]) } }
        case 2:
            if path.row == 0 { speech.setFollow(!speech.follow) }
            else { choose(title: "취침 타이머", labels: ["사용 안 함", "15분", "30분", "60분"]) { [weak self] index in self?.speech.setTimer([0, 15, 30, 60][index]) } }
        default:
            dismiss(animated: true) { [speech] in speech.start(savedPosition: true) }
        }
        tableView.reloadData()
    }
    private func choose(title: String, labels: [String], change: @escaping (Int) -> Void) {
        speech.stopPreview()
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        for (index, label) in labels.enumerated() { alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in change(index); self?.tableView.reloadData() }) }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }
}
