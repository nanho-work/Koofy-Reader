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
    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 2 }
        if section == 4 { return speech.hasSaved ? 1 : 0 }
        return 1
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["목소리", "읽기 속도", "취침 타이머", "본문 표시", "이어 듣기"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "기기에 설치된 한국어 음성을 사용합니다. 음성 추가: iPhone 설정 → 손쉬운 사용 → 읽기 및 말하기(또는 콘텐츠 말하기) → 음성 → 한국어. 다운로드 후 독서 화면을 다시 열어 주세요."
        case 3: return "앱·독서 화면을 벗어나거나 화면을 잠그면 멈춥니다. 돌아와도 자동으로 재생하지 않습니다."
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
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        switch path.section {
        case 0:
            if path.row == 0 {
                cell.textLabel?.text = speech.voices.first { $0.identifier == speech.voiceID }?.name ?? "로컬 음성을 선택해 주세요"
                cell.detailTextLabel?.text = speech.voices.isEmpty ? "설치된 한국어 음성이 없습니다." : "한국어 · 기기 음성"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "선택한 음성 미리 듣기"
                cell.imageView?.image = UIImage(systemName: "play.circle")
                cell.imageView?.tintColor = palette.accent
            }
        case 1:
            let speeds = [0.75, 1.0, 1.25, 1.5, 2.0]
            installChoices(in: cell, labels: ["0.75배", "1배", "1.25배", "1.5배", "2배"], selected: speeds.firstIndex(of: speech.speed)) { [weak self] in self?.speech.setSpeed(speeds[$0]) }
        case 2:
            let minutes = [0, 15, 30, 60]
            installChoices(in: cell, labels: ["꺼짐", "15분", "30분", "60분"], selected: minutes.firstIndex(of: speech.timerMinutes)) { [weak self] in self?.speech.setTimer(minutes[$0]) }
        case 3:
            cell.textLabel?.text = "음성을 따라 페이지 이동"
            // A wrapping row remains accessible at the largest text size.
            cell.accessoryType = speech.follow ? .checkmark : .none
            cell.accessibilityTraits = [.button]
            cell.accessibilityValue = speech.follow ? "켜짐" : "꺼짐"
        default:
            cell.textLabel?.text = "저장된 듣던 위치부터 재생"
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    private func installChoices(in cell: UITableViewCell, labels: [String], selected: Int?, change: @escaping (Int) -> Void) {
        cell.selectionStyle = .none
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        let row = UIStackView(); row.translatesAutoresizingMaskIntoConstraints = false; row.spacing = 8
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        for (index, label) in labels.enumerated() {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = label
            configuration.baseForegroundColor = index == selected ? palette.background : palette.foreground
            configuration.background.backgroundColor = index == selected ? palette.accent : palette.background
            configuration.background.cornerRadius = 12
            configuration.contentInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes; result.font = font; return result
            }
            button.configuration = configuration
            button.isSelected = index == selected
            button.accessibilityLabel = label
            button.accessibilityValue = index == selected ? "선택됨" : nil
            button.addAction(UIAction { [weak self] _ in change(index); self?.tableView.reloadData() }, for: .touchUpInside)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
            row.addArrangedSubview(button)
        }
        scroll.addSubview(row); cell.contentView.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
            scroll.heightAnchor.constraint(equalToConstant: max(48, font.lineHeight + 24)),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        switch path.section {
        case 0:
            if path.row == 1 { speech.preview() }
            else if !speech.voices.isEmpty {
                speech.stopPreview()
                let voices = speech.voices
                let alert = UIAlertController(title: "한국어 목소리 선택", message: nil, preferredStyle: .alert)
                for voice in voices {
                    alert.addAction(UIAlertAction(title: "\(voice.identifier == speech.voiceID ? "✓ " : "")\(voice.name)", style: .default) { [weak self] _ in
                        self?.speech.selectVoice(voice.identifier); self?.tableView.reloadData()
                    })
                }
                alert.addAction(UIAlertAction(title: "닫기", style: .cancel))
                present(alert, animated: true)
            }
        case 3: speech.setFollow(!speech.follow); tableView.reloadData()
        case 4: dismiss(animated: true) { [speech] in speech.start(savedPosition: true) }
        default: break
        }
    }
}
