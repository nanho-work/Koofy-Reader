import UIKit

/// Flat, single-open accordion. Preference changes retain the original reading anchor.
final class ReaderSettingsViewController: UITableViewController {
    var onStartAuto: (() -> Void)?
    var onStartSpeech: (() -> Void)?
    var onEndSpeech: (() -> Void)?
    var onManageFonts: (() -> Void)?
    var onSpeechVisibility: (() -> Void)?
    var canShowSpread: () -> Bool = { true }
    var previewFont: (String) -> UIFont? = { _ in nil }
    var onSpeech: (() -> Void)?
    var onTranslation: (() -> Void)?
    var translationEnabled = false
    private var expanded: Int?
    private var preferences: ReaderPreferences
    private let change: (ReaderPreferences, @escaping (Result<Void, Error>) -> Void) -> Void
    private let fontIds: [String]
    private let fontLabels: [String]
    private var busy = false
    private var errorMessage: String?
    private var autoDraft: String?
    private let panelTransition = ReaderSettingsTransition()
    private let titles = ["글자·글꼴", "줄·문단 간격", "페이지 여백", "독서 배경", "페이지 넘김", "자동 넘김", "하단 정보", "듣기", "번역"]

    init(preferences: ReaderPreferences,
         fontIds: [String] = ReaderFonts.ids, fontLabels: [String] = ReaderFonts.labels,
         change: @escaping (ReaderPreferences, @escaping (Result<Void, Error>) -> Void) -> Void) {
        self.fontIds = fontIds; self.fontLabels = fontLabels
        self.preferences = preferences; self.change = change
        super.init(style: .plain)
        title = L("독서 설정")
    }
    required init?(coder: NSCoder) { fatalError("Use init(preferences:change:)") }

    func makePanel() -> UINavigationController {
        let navigation = UINavigationController(rootViewController: self)
        navigation.modalPresentationStyle = .custom
        navigation.transitioningDelegate = panelTransition
        return navigation
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.view.accessibilityViewIsModal = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: L("닫기") + " ×", style: .plain, target: self, action: #selector(closePanel))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68
        tableView.sectionHeaderHeight = .leastNormalMagnitude
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.keyboardDismissMode = .interactive
        if #available(iOS 15.0, *) { tableView.sectionHeaderTopPadding = 0 }
        refresh()
    }
    private func summary(_ section: Int) -> String {
        let p = preferences
        switch section {
        case 0:
            let index = fontIds.firstIndex(of: p.fontId ?? "default") ?? 0
            return String(format: "%.0f%%", p.fontScale * 100) + " · " + (fontLabels.indices.contains(index) ? fontLabels[index] : L("기본"))
        case 1: return L("줄간격") + " · " + (p.lineHeight.map { String(format: "%.2f×", $0) } ?? L("책 기본값"))
        case 2: return [L("기본"), L("좁게"), L("보통"), L("넓게")][[nil, 0.5, 1, 1.5].firstIndex(of: p.pageMargins) ?? 0]
        case 3: return L(["밝게", "종이색", "어둡게"][["light", "sepia", "dark"].firstIndex(of: ReaderTheme.resolve(p.theme)) ?? 0])
        case 4: return p.scroll ? L("연속 스크롤") : p.pageTurnStyle == "curl" ? L("책장 넘기기") : L("바로 넘기기")
        case 5: return L("넘김 간격: {0}초", String(p.autoTurnSeconds ?? 30))
        case 6: return p.footerInfo == "none" ? L("없음") : L("진행률")
        case 7: return L("목소리·속도·타이머")
        default: return translationEnabled ? L("켜짐") : L("꺼짐")
        }
    }
    private func refresh() {
        guard isViewLoaded else { return }
        let offset = tableView.contentOffset
        let palette = ReaderPalette.forTheme(preferences.theme)
        overrideUserInterfaceStyle = ReaderTheme.style(preferences.theme)
        navigationController?.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        tableView.backgroundColor = palette.background; tableView.tintColor = palette.accent
        tableView.separatorColor = palette.secondary.withAlphaComponent(0.18)
        tableView.isUserInteractionEnabled = !busy
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground(); appearance.backgroundColor = palette.background
        appearance.shadowColor = palette.secondary.withAlphaComponent(0.18)
        appearance.titleTextAttributes = [.foregroundColor: palette.foreground]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = palette.accent
        // Never change the navigation bar's height while applying a setting.
        navigationItem.prompt = nil
        if busy {
            let spinner = UIActivityIndicatorView(style: .medium); spinner.color = palette.accent
            spinner.accessibilityLabel = L("읽던 위치에 적용 중…"); spinner.startAnimating()
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: spinner)
        } else { navigationItem.leftBarButtonItem = nil }
        if let message = errorMessage {
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 88))
            label.text = message; label.numberOfLines = 0; label.textColor = palette.foreground
            label.font = .preferredFont(forTextStyle: .footnote); label.adjustsFontForContentSizeCategory = true
            tableView.tableFooterView = label
        } else { tableView.tableFooterView = UIView(frame: .zero) }
        tableView.reloadData(); tableView.layoutIfNeeded()
        let minY = -tableView.adjustedContentInset.top
        let maxY = max(minY, tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom)
        tableView.setContentOffset(CGPoint(x: 0, y: min(maxY, max(minY, offset.y))), animated: false)
    }
    private func update(_ edit: (inout ReaderPreferences) -> Void) {
        guard !busy else { return }
        var next = preferences; edit(&next)
        commit(next)
    }
    private func commit(_ next: ReaderPreferences, after: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true; errorMessage = nil; refresh()
        change(next) { [weak self] result in
            guard let self else { return }
            self.busy = false
            switch result {
            case .success: self.preferences = next
            case .failure:
                self.errorMessage = L("설정을 적용하지 못했습니다. 다시 시도해 주세요.")
                UIAccessibility.post(notification: .announcement, argument: self.errorMessage)
            }
            self.refresh()
            if case .success = result { after?() }
        }
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.refresh() }
    }
    private func settingSection(_ index: Int) -> Int { index }

    override func numberOfSections(in tableView: UITableView) -> Int { titles.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let id = settingSection(section)
        guard expanded == id else { return 1 }
        return 1 + [fontIds.count + 2, 2, 1, 1, 3, 2, 1, 4, 1][id]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let id = settingSection(section)
        guard expanded == id else { return nil }
        switch id {
        case 1, 2: return L("기본은 책의 원래 설정입니다. 간격과 여백 변경은 모든 책에 적용됩니다.")
        case 4: return preferences.scroll ? L("연속 스크롤에서는 페이지 배치와 전환 효과를 사용하지 않습니다. 선택한 설정은 유지됩니다.") : L("두 페이지 선택은 넓은 화면에서 표시됩니다.")
        case 5: return preferences.scroll ? L("연속 스크롤에서는 자동 넘김을 사용할 수 없습니다.") : nil
        case 7: return L("듣기를 시작하면 조작 버튼이 표시됩니다. 일시정지 후에도 유지되며, 듣기 종료를 누르면 숨겨집니다.")
        case 8: return L("모드를 켠 뒤 본문을 길게 눌러 단어나 문장을 선택하세요. 번역은 하단에 표시됩니다.")
        default: return nil
        }
    }
    private func mount(_ control: UIView, in cell: UITableViewCell) {
        control.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            control.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            control.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            control.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }
    private func text(_ title: String) -> UILabel {
        let label = UILabel(); label.text = title; label.numberOfLines = 0
        label.textColor = ReaderPalette.forTheme(preferences.theme).foreground
        label.font = .preferredFont(forTextStyle: .subheadline); label.adjustsFontForContentSizeCategory = true
        return label
    }
    private func action(_ title: String, selected: Bool = false, enabled: Bool = true, identifier: String? = nil, perform: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = (selected ? "✓ " : "") + title
        config.titleAlignment = .leading
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        config.baseForegroundColor = selected ? ReaderPalette.forTheme(preferences.theme).accent : ReaderPalette.forTheme(preferences.theme).foreground
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var next = attributes; next.font = UIFont.preferredFont(forTextStyle: .subheadline); return next
        }
        button.configuration = config; button.contentHorizontalAlignment = .leading
        button.titleLabel?.numberOfLines = 0; button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.isEnabled = enabled && !busy; button.alpha = button.isEnabled ? 1 : 0.4
        button.accessibilityIdentifier = identifier
        if selected { button.accessibilityTraits.insert(.selected) }
        button.addAction(UIAction { _ in perform() }, for: .touchUpInside)
        return button
    }
    private func choices(_ title: String?, _ labels: [String], selected: Int, setting: Int, enabled: Bool = true, unavailable: Set<Int> = []) -> UIView {
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 2
        if let title { stack.addArrangedSubview(text(title)) }
        for (index, label) in labels.enumerated() {
            stack.addArrangedSubview(action(label, selected: index == selected, enabled: enabled && !unavailable.contains(index), identifier: "reader.setting.\(setting).\(index)") { [weak self] in self?.choose(setting, index) })
        }
        return stack
    }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let palette = ReaderPalette.forTheme(preferences.theme)
        let cell = UITableViewCell(style: path.row == 0 ? .subtitle : .default, reuseIdentifier: nil)
        cell.backgroundColor = palette.background; cell.tintColor = palette.accent
        cell.textLabel?.textColor = palette.foreground; cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body); cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.selectionStyle = .none
        if path.row == 0 {
            cell.textLabel?.text = L(titles[path.section]); cell.detailTextLabel?.text = summary(settingSection(path.section))
            cell.detailTextLabel?.font = .preferredFont(forTextStyle: .caption1)
            cell.detailTextLabel?.adjustsFontForContentSizeCategory = true; cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = palette.secondary
            cell.contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
            cell.accessoryView = UIImageView(image: UIImage(systemName: expanded == settingSection(path.section) ? "chevron.up" : "chevron.down"))
            cell.selectionStyle = .default; cell.accessibilityTraits = .button
            cell.accessibilityIdentifier = "reader.settings.section.\(settingSection(path.section))"
            cell.accessibilityValue = summary(settingSection(path.section)) + ", " + (expanded == settingSection(path.section) ? L("접기") : L("펼치기"))
            return cell
        }
        let row = path.row - 1
        if settingSection(path.section) == 7 {
            cell.textLabel?.text = [L("▶ 듣기 시작 / 재개"), L("목소리·속도·타이머"), L("듣기 종료"), L("듣기 버튼 항상 표시")][row]
            if row == 3 {
                let toggle = UISwitch(); toggle.onTintColor = palette.accent
                toggle.isOn = UserDefaults.standard.bool(forKey: "reader.speech.alwaysShow")
                toggle.addAction(UIAction { [weak self] _ in UserDefaults.standard.set(toggle.isOn, forKey: "reader.speech.alwaysShow"); self?.onSpeechVisibility?() }, for: .valueChanged)
                cell.accessoryView = toggle
            } else { cell.selectionStyle = .default; cell.accessoryType = .disclosureIndicator }
            return cell
        }
        if settingSection(path.section) == 8 {
            cell.textLabel?.text = L("번역 모드")
            let toggle = UISwitch(); toggle.onTintColor = palette.accent; toggle.isOn = translationEnabled
            toggle.addAction(UIAction { [weak self] _ in self?.onTranslation?() }, for: .valueChanged)
            cell.accessoryView = toggle; return cell
        }
        if settingSection(path.section) == 5 {
            if row == 0 {
                cell.textLabel?.text = L("자동 넘김 시작"); cell.textLabel?.textColor = preferences.scroll ? palette.secondary : palette.accent
                cell.isUserInteractionEnabled = !preferences.scroll && !busy; cell.selectionStyle = .default
            } else {
                let field = UITextField(); field.keyboardType = .numberPad
                field.text = autoDraft ?? String(preferences.autoTurnSeconds ?? 30)
                field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
                field.textColor = palette.foreground; field.accessibilityLabel = L("넘김 간격 (초)")
                field.accessibilityIdentifier = "reader.settings.autoInterval"
                field.addAction(UIAction { [weak self, weak field] _ in self?.autoDraft = field?.text }, for: .editingChanged)
                field.isEnabled = !preferences.scroll && !busy
                let save = action(L("저장"), enabled: !preferences.scroll) { [weak self, weak field] in
                    guard let self else { return }
                    guard let seconds = Int64(field?.text ?? ""), (5...300).contains(seconds) else {
                        self.errorMessage = L("5~300초로 입력해 주세요."); UIAccessibility.post(notification: .announcement, argument: self.errorMessage); self.refresh(); return
                    }
                    self.view.endEditing(true); self.autoDraft = nil; self.update { $0.autoTurnSeconds = seconds }
                }
                let input = UIStackView(arrangedSubviews: [field, save]); input.spacing = 12
                let stack = UIStackView(arrangedSubviews: [text(L("넘김 간격 (초) · 5~300")), input]); stack.axis = .vertical; stack.spacing = 8
                mount(stack, in: cell)
            }
            return cell
        }
        if settingSection(path.section) == 0 && row > 0 {
            if row == fontIds.count + 1 {
                cell.textLabel?.text = L("＋ 내 글꼴 추가·관리"); cell.accessoryType = .disclosureIndicator; cell.selectionStyle = .default
            } else {
                let index = row - 1, id = fontIds[row - 1]
                cell.textLabel?.text = fontLabels[index] + "\n" + L("오늘도 한 페이지를 읽습니다.") + (id.hasPrefix("personal_") ? L(" · 내 글꼴") : id.hasPrefix("remote_") ? L(" · 다운로드") : "")
                cell.textLabel?.font = previewFont(id) ?? .preferredFont(forTextStyle: .body)
                let selected = fontIds.contains(preferences.fontId ?? "default") ? preferences.fontId ?? "default" : "default"
                cell.accessoryType = id == selected ? .checkmark : .none; cell.selectionStyle = .default
            }
            cell.isUserInteractionEnabled = !busy
            return cell
        }
        let control: UIView
        switch settingSection(path.section) {
        case 0:
            let minus = action("A−", enabled: preferences.fontScale > 0.5) { [weak self] in self?.update { $0.fontScale = max(0.5, $0.fontScale - 0.1) } }
            minus.accessibilityLabel = L("글자 작게")
            let plus = action("A+", enabled: preferences.fontScale < 3) { [weak self] in self?.update { $0.fontScale = min(3, $0.fontScale + 0.1) } }
            plus.accessibilityLabel = L("글자 크게")
            let value = text(String(format: "%.0f%%", preferences.fontScale * 100)); value.textAlignment = .center
            let stack = UIStackView(arrangedSubviews: [minus, value, plus]); stack.distribution = .fillEqually
            control = stack
        case 1 where row == 0:
            let value = text(preferences.lineHeight.map { String(format: "%.2f×", $0) } ?? L("기본")); value.textAlignment = .center
            let original = action(L("책 기본값"), selected: preferences.lineHeight == nil) { [weak self] in self?.update { $0.lineHeight = nil } }
            let stepper = UIStepper(); stepper.minimumValue = 1; stepper.maximumValue = 3; stepper.stepValue = 0.05
            stepper.value = preferences.lineHeight ?? 1.5; stepper.accessibilityLabel = L("줄간격")
            stepper.addAction(UIAction { [weak self] _ in self?.update { $0.lineHeight = (stepper.value * 20).rounded() / 20 } }, for: .valueChanged)
            let row = UIStackView(arrangedSubviews: [value, stepper]); row.alignment = .center; row.spacing = 8
            let slider = UISlider(); slider.minimumValue = 1; slider.maximumValue = 3; slider.value = Float(preferences.lineHeight ?? 1.5)
            slider.isContinuous = false; slider.accessibilityLabel = L("줄간격")
            slider.addAction(UIAction { [weak self] _ in self?.update { $0.lineHeight = (Double(slider.value) * 20).rounded() / 20 } }, for: .valueChanged)
            let stack = UIStackView(arrangedSubviews: [text(L("줄간격")), original, row, slider]); stack.axis = .vertical; stack.spacing = 10
            control = stack
        case 1: control = choices(L("문단 간격"), [L("기본"), L("없음"), L("보통"), L("넓게")], selected: [nil, 0, 0.5, 1].firstIndex(of: preferences.paragraphSpacing) ?? 0, setting: 7)
        case 2: control = choices(nil, [L("기본"), L("좁게"), L("보통"), L("넓게")], selected: [nil, 0.5, 1, 1.5].firstIndex(of: preferences.pageMargins) ?? 0, setting: 8)
        case 3: control = choices(nil, [L("밝게"), L("종이색"), L("어둡게")], selected: ["light", "sepia", "dark"].firstIndex(of: ReaderTheme.resolve(preferences.theme)) ?? 0, setting: 10)
        case 4 where row == 0: control = choices(L("넘김 방식"), [L("페이지 넘김"), L("연속 스크롤")], selected: preferences.scroll ? 1 : 0, setting: 2)
        case 4 where row == 1: control = choices(L("페이지 배치"), [L("자동"), L("한 페이지"), L("두 페이지")], selected: Int(preferences.columnCount), setting: 3, enabled: !preferences.scroll, unavailable: canShowSpread() ? [] : [2])
        case 4: control = choices(L("페이지 전환 효과"), [L("바로 넘기기"), L("책장 넘기기")], selected: preferences.pageTurnStyle == "curl" ? 1 : 0, setting: 4, enabled: !preferences.scroll)
        default: control = choices(nil, [L("없음"), L("진행률")], selected: preferences.footerInfo == "none" ? 0 : 1, setting: 9)
        }
        control.tintColor = palette.accent; control.isUserInteractionEnabled = !busy
        mount(control, in: cell)
        return cell
    }
    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { indexPath.row == 0 ? 72 : 120 }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        guard !busy else { return }
        if path.row == 0 {
            view.endEditing(true)
            expanded = expanded == settingSection(path.section) ? nil : settingSection(path.section)
            refresh()
            tableView.scrollToRow(at: IndexPath(row: 0, section: path.section), at: .top, animated: true)
            UIAccessibility.post(notification: .layoutChanged, argument: tableView.cellForRow(at: path))
            return
        }
        let row = path.row - 1
        if settingSection(path.section) == 7 { switch row { case 0: onStartSpeech?(); case 1: onSpeech?(); case 2: onEndSpeech?(); default: break }; return }
        if settingSection(path.section) == 5 && row == 0 {
            guard !preferences.scroll else { return }
            if let draft = autoDraft {
                guard let seconds = Int64(draft), (5...300).contains(seconds) else {
                    errorMessage = L("5~300초로 입력해 주세요.")
                    UIAccessibility.post(notification: .announcement, argument: errorMessage); refresh(); return
                }
                var next = preferences; next.autoTurnSeconds = seconds
                view.endEditing(true)
                commit(next) { [weak self] in self?.autoDraft = nil; self?.onStartAuto?() }
            } else { onStartAuto?() }
            return
        }
        if settingSection(path.section) == 0 && row > 0 {
            if row == fontIds.count + 1 { onManageFonts?() }
            else { update { $0.fontId = fontIds[row - 1] } }
        }
    }
    private func choose(_ setting: Int, _ index: Int) {
        guard !(preferences.scroll && (setting == 3 || setting == 4)), !(setting == 3 && index == 2 && !canShowSpread()) else { return }
        update {
            switch setting {
            case 10: $0.theme = ["light", "sepia", "dark"][index]
            case 2: $0.scroll = index == 1
            case 3: $0.columnCount = Int64(index)
            case 4: $0.pageTurnStyle = index == 1 ? "curl" : "instant"
            case 7: $0.paragraphSpacing = [nil, 0, 0.5, 1][index]
            case 8: $0.pageMargins = [nil, 0.5, 1, 1.5][index]
            default: $0.footerInfo = ["none", "progress"][index]
            }
        }
    }
    @objc private func closePanel() { dismiss(animated: true) }
}

/// A custom presentation keeps the underlying Readium view mounted at its exact size.
private final class ReaderSettingsTransition: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        ReaderSettingsPresentation(presentedViewController: presented, presenting: presenting)
    }
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? { ReaderSettingsAnimation(entering: true) }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? { ReaderSettingsAnimation(entering: false) }
}
final class ReaderSettingsPresentation: UIPresentationController {
    private let backdrop = UIControl()
    static func panelWidth(_ available: CGFloat) -> CGFloat {
        let pane = available >= 600 ? available / 2 : available
        return min(pane, max(min(240, pane), pane * 2 / 3))
    }
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let safe = container.bounds.inset(by: UIEdgeInsets(top: 0, left: container.safeAreaInsets.left, bottom: 0, right: container.safeAreaInsets.right))
        let width = Self.panelWidth(safe.width)
        return CGRect(x: safe.maxX - width, y: safe.minY, width: width, height: safe.height)
    }
    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        backdrop.frame = container.bounds; backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.33); backdrop.alpha = 0
        backdrop.accessibilityLabel = L("닫기"); backdrop.addTarget(self, action: #selector(close), for: .touchUpInside)
        container.insertSubview(backdrop, at: 0)
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 1 })
    }
    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 0 })
    }
    override func dismissalTransitionDidEnd(_ completed: Bool) { if completed { backdrop.removeFromSuperview() } }
    override func containerViewWillLayoutSubviews() {
        let frame = frameOfPresentedViewInContainerView
        // Bounds/center remain well-defined while the slide transform is active.
        presentedView?.bounds = CGRect(origin: .zero, size: frame.size)
        presentedView?.center = CGPoint(x: frame.midX, y: frame.midY)
        backdrop.frame = containerView?.bounds ?? .zero
    }
    @objc private func close() { presentedViewController.dismiss(animated: true) }
}
private final class ReaderSettingsAnimation: NSObject, UIViewControllerAnimatedTransitioning {
    let entering: Bool
    init(entering: Bool) { self.entering = entering }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0 : 0.22 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let controller = context.viewController(forKey: entering ? .to : .from), let panel = controller.view else { context.completeTransition(false); return }
        if entering {
            context.containerView.addSubview(panel)
            panel.frame = context.finalFrame(for: controller)
            panel.transform = CGAffineTransform(translationX: panel.bounds.width, y: 0)
        }
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            panel.transform = self.entering ? .identity : CGAffineTransform(translationX: panel.bounds.width, y: 0)
        }, completion: { _ in context.completeTransition(!context.transitionWasCancelled) })
    }
}
