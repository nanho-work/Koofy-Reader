import UIKit

/// Keeps settings open while the host applies preferences and restores its locator.
final class ReaderSettingsViewController: UITableViewController {
    var onSpeech: (() -> Void)?
    private var preferences: ReaderPreferences
    private let change: (ReaderPreferences, @escaping (Result<Void, Error>) -> Void) -> Void
    private let fontIds: [String]
    private let fontLabels: [String]
    private var busy = false
    private var errorMessage: String?

    init(preferences: ReaderPreferences,
         fontIds: [String] = ReaderFonts.ids, fontLabels: [String] = ReaderFonts.labels,
         change: @escaping (ReaderPreferences, @escaping (Result<Void, Error>) -> Void) -> Void) {
        self.fontIds = fontIds
        self.fontLabels = fontLabels
        self.preferences = preferences
        self.change = change
        super.init(style: .insetGrouped)
        title = "독서 설정"
    }
    required init?(coder: NSCoder) { fatalError("Use init(preferences:change:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "완료", style: .done,
            target: self, action: #selector(closeSheet))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "듣기 설정", style: .plain, target: self, action: #selector(speechTapped))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        refresh()
    }

    @objc private func speechTapped() { onSpeech?() }

    private func refresh() {
        let p = ReaderPalette.forTheme(preferences.theme)
        overrideUserInterfaceStyle = preferences.theme == "dark" ? .dark : .light
        navigationController?.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        tableView.backgroundColor = p.background
        tableView.tintColor = p.accent
        navigationItem.rightBarButtonItem?.tintColor = p.accent
        navigationController?.view.tintColor = p.accent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = p.background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: p.foreground]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = p.accent
        navigationItem.prompt = busy ? "읽던 위치에 적용 중…" : errorMessage
        tableView.reloadData()
    }

    private func update(_ edit: (inout ReaderPreferences) -> Void) {
        guard !busy else { return }
        var next = preferences
        edit(&next)
        busy = true
        errorMessage = nil
        refresh()
        change(next) { [weak self] result in
            guard let self else { return }
            self.busy = false
            switch result {
            case .success: self.preferences = next
            case .failure: self.errorMessage = "설정을 적용하지 못했습니다. 다시 시도해 주세요."
            }
            self.refresh()
        }
    }

    private func settingIndex(_ path: IndexPath) -> Int {
        path.section == 2 ? path.row + 2 : path.section == 3 ? path.row + 6 : path.section == 4 ? 5 : path.section
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 4 ? fontIds.count : (section == 2 || section == 3) ? 3 : 1
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["글자 크기", "배경", "읽기 방식", "본문 간격", "글꼴"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 3 { return "기본은 책의 원래 설정입니다. 줄·문단 간격을 지정하면 출판사 문단 스타일 일부가 바뀔 수 있습니다. 두 페이지에서는 좌우 여백과 중앙 간격이 함께 조절됩니다." }
        guard section == 2 else { return nil }
        return preferences.scroll
            ? "연속 스크롤에서는 페이지 배치와 전환 효과를 사용하지 않습니다. 선택한 설정은 유지됩니다."
            : "두 페이지는 화면 너비가 충분할 때 적용됩니다. 책장 넘기기는 가장자리를 잡고 밀어 넘길 수 있습니다."
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let setting = settingIndex(indexPath)
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let palette = ReaderPalette.forTheme(preferences.theme)
        cell.backgroundColor = palette.panel
        cell.selectionStyle = .none
        if setting == 5 {
            cell.textLabel?.text = fontLabels[indexPath.row]
            cell.textLabel?.textColor = palette.foreground
            cell.textLabel?.numberOfLines = 0
            cell.accessoryType = fontIds[indexPath.row] == (fontIds.contains(preferences.fontId ?? "default") ? (preferences.fontId ?? "default") : "default") ? .checkmark : .none
            cell.tintColor = palette.accent
            cell.isUserInteractionEnabled = !busy
            cell.selectionStyle = .default
            return cell
        }
        let control: UIView
        if setting == 0 {
            let minus = UIButton(type: .system)
            minus.setTitle("A−", for: .normal)
            minus.accessibilityLabel = "글자 작게"
            minus.addTarget(self, action: #selector(smaller), for: .touchUpInside)
            let value = UILabel()
            value.text = String(format: "%.0f%%", preferences.fontScale * 100)
            value.font = .preferredFont(forTextStyle: .body)
            value.adjustsFontForContentSizeCategory = true
            value.textColor = palette.foreground
            value.textAlignment = .center
            let plus = UIButton(type: .system)
            plus.setTitle("A+", for: .normal)
            plus.accessibilityLabel = "글자 크게"
            plus.addTarget(self, action: #selector(larger), for: .touchUpInside)
            minus.isEnabled = !busy && preferences.fontScale > 0.5
            plus.isEnabled = !busy && preferences.fontScale < 3
            let stack = UIStackView(arrangedSubviews: [minus, value, plus])
            stack.distribution = .fillEqually
            control = stack
        } else if setting >= 6 {
            let labels = [["기본", "촘촘", "보통", "넉넉"], ["기본", "없음", "보통", "넓게"], ["기본", "좁게", "보통", "넓게"]]
            let values: [[Double?]] = [[nil, 1.2, 1.5, 1.8], [nil, 0, 0.5, 1], [nil, 0.5, 1, 1.5]]
            let selected = [preferences.lineHeight, preferences.paragraphSpacing, preferences.pageMargins][setting - 6]
            let segment = UISegmentedControl(items: labels[setting - 6])
            segment.tag = setting + 1
            segment.selectedSegmentIndex = values[setting - 6].firstIndex(of: selected) ?? UISegmentedControl.noSegment
            segment.selectedSegmentTintColor = palette.background
            segment.setTitleTextAttributes([.foregroundColor: palette.foreground], for: .normal)
            segment.isEnabled = !busy
            segment.addTarget(self, action: #selector(selected(_:)), for: .valueChanged)
            let label = UILabel()
            label.text = ["줄간격", "문단 간격", "페이지 여백"][setting - 6]
            label.textColor = palette.foreground
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
            segment.accessibilityLabel = label.text
            let stack = UIStackView(arrangedSubviews: [label, segment])
            stack.axis = .vertical; stack.spacing = 8
            control = stack
        } else {
            let labels = [["밝게", "종이색", "어둡게"], ["페이지 넘김", "연속 스크롤"], ["자동", "한 페이지", "두 페이지"], ["바로 넘기기", "책장 넘기기"]]
            let segment = UISegmentedControl(items: labels[setting - 1])
            // Keep action identifiers independent of the displayed section order.
            segment.tag = setting + 1
            segment.accessibilityLabel = ["", "배경", "읽기 방식", "페이지 배치", "페이지 전환 효과"][setting]
            segment.selectedSegmentIndex = segment.tag == 2
                ? (["light", "sepia", "dark"].firstIndex(of: preferences.theme) ?? 1)
                : segment.tag == 3 ? (preferences.scroll ? 1 : 0)
                : segment.tag == 4 ? Int(preferences.columnCount) : (preferences.pageTurnStyle == "curl" ? 1 : 0)
            segment.selectedSegmentTintColor = palette.background
            segment.setTitleTextAttributes([.foregroundColor: palette.foreground], for: .normal)
            segment.isEnabled = !busy && !((segment.tag == 4 || segment.tag == 5) && preferences.scroll)
            segment.addTarget(self, action: #selector(selected(_:)), for: .valueChanged)
            if setting >= 2 {
                let label = UILabel()
                label.text = ["넘김 방식", "페이지 배치", "페이지 전환 효과"][setting - 2]
                label.font = .preferredFont(forTextStyle: .subheadline)
                label.textColor = palette.foreground
                label.adjustsFontForContentSizeCategory = true
                let stack = UIStackView(arrangedSubviews: [label, segment])
                stack.axis = .vertical
                stack.spacing = 8
                control = stack
            } else { control = segment }
        }
        control.tintColor = palette.accent
        control.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
            control.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),
            control.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            control.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard settingIndex(indexPath) == 5 else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        update { $0.fontId = fontIds[indexPath.row] }
    }
    @objc private func smaller() { update { $0.fontScale = max(0.5, $0.fontScale - 0.1) } }
    @objc private func larger() { update { $0.fontScale = min(3, $0.fontScale + 0.1) } }
    @objc private func selected(_ control: UISegmentedControl) {
        guard !(preferences.scroll && (control.tag == 4 || control.tag == 5)) else { return }
        update {
            switch control.tag {
            case 7: $0.lineHeight = [nil, 1.2, 1.5, 1.8][control.selectedSegmentIndex]
            case 8: $0.paragraphSpacing = [nil, 0, 0.5, 1][control.selectedSegmentIndex]
            case 9: $0.pageMargins = [nil, 0.5, 1, 1.5][control.selectedSegmentIndex]
            case 2: $0.theme = ["light", "sepia", "dark"][control.selectedSegmentIndex]
            case 3: $0.scroll = control.selectedSegmentIndex == 1
            case 5: $0.pageTurnStyle = control.selectedSegmentIndex == 1 ? "curl" : "instant"
            default: $0.columnCount = Int64(control.selectedSegmentIndex)
            }
        }
    }
    @objc private func closeSheet() { dismiss(animated: true) }
}
