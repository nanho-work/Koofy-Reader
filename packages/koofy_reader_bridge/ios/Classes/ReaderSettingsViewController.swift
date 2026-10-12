import UIKit

/// Keeps settings open while the host applies preferences and restores its locator.
final class ReaderSettingsViewController: UITableViewController {
    var onStartSpeech: (() -> Void)?
    var onEndSpeech: (() -> Void)?
    var onManageFonts: (() -> Void)?
    var onSpeechVisibility: (() -> Void)?
    var canShowSpread: () -> Bool = { true }
    var previewFont: (String) -> UIFont? = { _ in nil }
    private var detailsExpanded = false
    private var selectedPanel = 0
    var onSpeech: (() -> Void)?
    var onTranslation: (() -> Void)?
    var translationEnabled = false
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
        title = L("독서 설정")
    }
    required init?(coder: NSCoder) { fatalError("Use init(preferences:change:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: L("완료"), style: .done,
            target: self, action: #selector(closeSheet))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        let tabs = UISegmentedControl(items: [L("보기"), L("듣기"), L("번역")])
        tabs.selectedSegmentIndex = 0
        tabs.addAction(UIAction { [weak self] _ in self?.selectedPanel = tabs.selectedSegmentIndex; self?.refresh() }, for: .valueChanged)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 380, height: 60))
        tabs.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(tabs)
        NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            tabs.topAnchor.constraint(equalTo: header.topAnchor, constant: 8), tabs.heightAnchor.constraint(equalToConstant: 44)])
        tableView.tableHeaderView = header
        refresh()
    }

    @objc private func translationTapped() { onTranslation?() }

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
        navigationItem.prompt = busy ? L("읽던 위치에 적용 중…") : errorMessage
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
            case .failure: self.errorMessage = L("설정을 적용하지 못했습니다. 다시 시도해 주세요.")
            }
            self.refresh()
        }
    }

    private func settingIndex(_ path: IndexPath) -> Int {
        path.section == 2 ? path.row + 2 : path.section == 4 ? path.row + 6 : path.section == 5 ? 5 : path.section
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.refresh() }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { selectedPanel == 0 ? 6 : 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if selectedPanel == 1 { return 4 }
        if selectedPanel == 2 { return 1 }
        if section == 3 { return 1 }
        if section == 4 { return detailsExpanded ? 3 : 0 }
        if section == 5 { return detailsExpanded ? fontIds.count + 1 : 0 }
        return section == 2 ? 3 : 1
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if selectedPanel != 0 { return nil }
        if section >= 4 && !detailsExpanded { return nil }
        return [L("글자 크기"), L("배경"), L("읽기 방식"), "", L("본문 간격"), L("글꼴")][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if selectedPanel == 1 { return L("듣기를 시작하면 조작 버튼이 표시됩니다. 일시정지 후에도 유지되며, 듣기 종료를 누르면 숨겨집니다.") }
        if selectedPanel == 2 { return L("모드를 켠 뒤 본문을 길게 눌러 단어나 문장을 선택하세요. 번역은 하단에 표시됩니다.") }
        if section == 4 && detailsExpanded { return L("기본은 책의 원래 설정입니다. 간격과 여백 변경은 모든 책에 적용됩니다.") }
        guard section == 2 else { return nil }
        if preferences.scroll { return L("연속 스크롤에서는 페이지 배치와 전환 효과를 사용하지 않습니다. 선택한 설정은 유지됩니다.") }
        return !canShowSpread() && preferences.columnCount == 2
            ? L("현재 한 페이지로 표시 중 · 화면을 넓히면 두 페이지로 돌아갑니다.")
            : L("두 페이지 선택은 넓은 화면에서 표시됩니다.")
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let setting = settingIndex(indexPath)
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let palette = ReaderPalette.forTheme(preferences.theme)
        cell.backgroundColor = palette.panel
        cell.selectionStyle = .none
        cell.textLabel?.textColor = palette.foreground
        cell.textLabel?.numberOfLines = 0
        if selectedPanel == 1 {
            cell.textLabel?.text = [L("▶ 듣기 시작 / 재개"), L("목소리·속도·타이머"), L("듣기 종료"), L("듣기 버튼 항상 표시")][indexPath.row]
            if indexPath.row == 3 {
                let toggle = UISwitch(); toggle.onTintColor = palette.accent
                toggle.isOn = UserDefaults.standard.bool(forKey: "reader.speech.alwaysShow")
                toggle.addAction(UIAction { [weak self] _ in
                    UserDefaults.standard.set(toggle.isOn, forKey: "reader.speech.alwaysShow"); self?.onSpeechVisibility?()
                }, for: .valueChanged)
                cell.accessoryView = toggle
            } else { cell.accessoryType = .disclosureIndicator; cell.selectionStyle = .default }
            return cell
        }
        if selectedPanel == 2 {
            cell.textLabel?.text = L("번역 모드")
            let toggle = UISwitch(); toggle.onTintColor = palette.accent; toggle.isOn = translationEnabled
            toggle.addAction(UIAction { [weak self] _ in self?.onTranslation?() }, for: .valueChanged)
            cell.accessoryView = toggle; return cell
        }
        if indexPath.section == 3 {
            cell.textLabel?.text = detailsExpanded ? L("글꼴·문단 설정  ▴") : L("글꼴·문단 설정  ▾")
            cell.selectionStyle = .default; return cell
        }
        if indexPath.section == 5 && indexPath.row == fontIds.count {
            cell.textLabel?.text = L("＋ 내 글꼴 추가·관리")
            cell.accessoryType = .disclosureIndicator; cell.selectionStyle = .default; return cell
        }
        if setting == 5 {
            let id = fontIds[indexPath.row]
            cell.textLabel?.text = fontLabels[indexPath.row] + (id.hasPrefix("personal_") ? L(" · 내 글꼴") : id.hasPrefix("remote_") ? L(" · 다운로드") : "")
            cell.textLabel?.font = previewFont(id) ?? .preferredFont(forTextStyle: .body)
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
            minus.accessibilityLabel = L("글자 작게")
            minus.addTarget(self, action: #selector(smaller), for: .touchUpInside)
            let value = UILabel()
            value.text = String(format: "%.0f%%", preferences.fontScale * 100)
            value.font = .preferredFont(forTextStyle: .body)
            value.adjustsFontForContentSizeCategory = true
            value.textColor = palette.foreground
            value.textAlignment = .center
            let plus = UIButton(type: .system)
            plus.setTitle("A+", for: .normal)
            plus.accessibilityLabel = L("글자 크게")
            plus.addTarget(self, action: #selector(larger), for: .touchUpInside)
            minus.isEnabled = !busy && preferences.fontScale > 0.5
            plus.isEnabled = !busy && preferences.fontScale < 3
            for button in [minus, plus] {
                button.backgroundColor = palette.background; button.layer.cornerRadius = 10
                button.layer.borderWidth = 1; button.layer.borderColor = palette.secondary.withAlphaComponent(0.5).cgColor
            }
            let stack = UIStackView(arrangedSubviews: [minus, value, plus])
            stack.distribution = .fillEqually
            control = stack
        } else if setting >= 6 {
            let labels = [[L("기본"), L("촘촘"), L("보통"), L("넉넉")], [L("기본"), L("없음"), L("보통"), L("넓게")], [L("기본"), L("좁게"), L("보통"), L("넓게")]]
            let values: [[Double?]] = [[nil, 1.2, 1.5, 1.8], [nil, 0, 0.5, 1], [nil, 0.5, 1, 1.5]]
            let selected = [preferences.lineHeight, preferences.paragraphSpacing, preferences.pageMargins][setting - 6]
            let segment = UISegmentedControl(items: labels[setting - 6])
            segment.tag = setting + 1
            segment.selectedSegmentIndex = values[setting - 6].firstIndex(of: selected) ?? UISegmentedControl.noSegment
            segment.selectedSegmentTintColor = palette.accent
            segment.setTitleTextAttributes([.foregroundColor: palette.background], for: .selected)
            segment.setTitleTextAttributes([.foregroundColor: palette.foreground], for: .normal)
            segment.isEnabled = !busy
            segment.addTarget(self, action: #selector(selected(_:)), for: .valueChanged)
            let label = UILabel()
            label.text = [L("줄간격"), L("문단 간격"), L("페이지 여백")][setting - 6]
            label.textColor = palette.foreground
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
            segment.accessibilityLabel = label.text
            let stack = UIStackView(arrangedSubviews: [label, segment])
            stack.axis = .vertical; stack.spacing = 8
            control = stack
        } else {
            let labels = [[L("밝게"), L("종이색"), L("어둡게")], [L("페이지 넘김"), L("연속 스크롤")], (canShowSpread() ? [L("자동"), L("한 페이지"), L("두 페이지")] : [L("자동"), L("한 페이지")]), [L("바로 넘기기"), L("책장 넘기기")]]
            let segment = UISegmentedControl(items: labels[setting - 1])
            // Keep action identifiers independent of the displayed section order.
            segment.tag = setting + 1
            segment.accessibilityLabel = ["", L("배경"), L("읽기 방식"), L("페이지 배치"), L("페이지 전환 효과")][setting]
            segment.selectedSegmentIndex = segment.tag == 2
                ? (["light", "sepia", "dark"].firstIndex(of: preferences.theme) ?? 1)
                : segment.tag == 3 ? (preferences.scroll ? 1 : 0)
                : segment.tag == 4 ? (!canShowSpread() && preferences.columnCount == 2 ? UISegmentedControl.noSegment : Int(preferences.columnCount)) : (preferences.pageTurnStyle == "curl" ? 1 : 0)
            segment.selectedSegmentTintColor = palette.accent
            segment.setTitleTextAttributes([.foregroundColor: palette.background], for: .selected)
            segment.setTitleTextAttributes([.foregroundColor: palette.foreground], for: .normal)
            segment.isEnabled = !busy && !((segment.tag == 4 || segment.tag == 5) && preferences.scroll)
            segment.addTarget(self, action: #selector(selected(_:)), for: .valueChanged)
            if setting >= 2 {
                let label = UILabel()
                label.text = [L("넘김 방식"), L("페이지 배치"), L("페이지 전환 효과")][setting - 2]
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
        if selectedPanel == 1 {
            switch indexPath.row { case 0: onStartSpeech?(); case 1: onSpeech?(); case 2: onEndSpeech?(); default: break }; return
        }
        if selectedPanel == 2 { return }
        if indexPath.section == 3 { detailsExpanded.toggle(); refresh(); return }
        if indexPath.section == 5 && indexPath.row == fontIds.count { onManageFonts?(); return }
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
