import UIKit

/// Reader counterpart of reader_alert.dart. OS permission UI is not replaced.
@MainActor final class ReaderAlertAction {
    let title: String?
    let style: UIAlertAction.Style
    let handler: ((ReaderAlertAction) -> Void)?
    init(title: String?, style: UIAlertAction.Style, handler: ((ReaderAlertAction) -> Void)? = nil) {
        self.title = title; self.style = style; self.handler = handler
    }
}

@MainActor final class ReaderAlertController: UIViewController {
    private let heading: String?
    private let message: String?
    private let palette: ReaderPalette
    private var actions: [ReaderAlertAction] = []
    private(set) var textFields: [UITextField]?
    private let card = UIView()
    private let headingLabel = UILabel()
    private var closing = false
    private weak var group: QueueGroup?
    var isDismissible = true

    init(title: String?, message: String?, preferredStyle: UIAlertController.Style = .alert, palette: ReaderPalette) {
        self.heading = title; self.message = message; self.palette = palette
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        isModalInPresentation = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(title:message:palette:)") }

    func addAction(_ action: ReaderAlertAction) { actions.append(action) }
    func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {
        let field = UITextField()
        configurationHandler?(field)
        textFields = (textFields ?? []) + [field]
    }

    func present(from presenter: UIViewController) {
        guard group == nil else { return }
        var owner = (presenter as? ReaderAlertController)?.group?.owner ?? presenter
        while let presented = owner.presentedViewController, !presented.isBeingDismissed {
            if presented is ReaderAlertController { break }
            owner = presented
        }
        let queue = Self.queues.object(forKey: owner) ?? QueueGroup(owner: owner)
        Self.queues.setObject(queue, forKey: owner)
        group = queue; queue.items.append(self); Self.observeActivation(); queue.advance()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        view.accessibilityViewIsModal = true
        let outsideTap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        outsideTap.cancelsTouchesInView = false; view.addGestureRecognizer(outsideTap)
        card.backgroundColor = palette.background
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 0.7
        card.layer.borderColor = palette.secondary.withAlphaComponent(0.16).cgColor
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        let centered = card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        centered.priority = .defaultHigh
        let width = card.widthAnchor.constraint(equalToConstant: 440)
        width.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor), centered, width,
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -24),
        ])
        let root = UIStackView(); root.axis = .vertical; root.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: card.trailingAnchor), root.topAnchor.constraint(equalTo: card.topAnchor),
            root.bottomAnchor.constraint(equalTo: card.bottomAnchor)])
        let content = UIStackView(); content.axis = .vertical; content.spacing = 12
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24)
        if let heading, !heading.isEmpty {
            headingLabel.text = heading; headingLabel.numberOfLines = 0
            headingLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 18, weight: .semibold))
            headingLabel.adjustsFontForContentSizeCategory = true; headingLabel.textColor = palette.foreground
            headingLabel.accessibilityTraits.insert(.header); content.addArrangedSubview(headingLabel)
        }
        if let message, !message.isEmpty {
            let label = UILabel(); label.numberOfLines = 0
            let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 14))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineHeightMultiple = 1.55
            label.attributedText = NSAttributedString(string: message, attributes: [.font: font,
                .foregroundColor: palette.foreground, .paragraphStyle: paragraph])
            label.adjustsFontForContentSizeCategory = true; content.addArrangedSubview(label)
        }
        for field in textFields ?? [] {
            field.font = UIFont.preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.textColor = palette.foreground; field.tintColor = palette.accent
            field.borderStyle = .roundedRect; field.backgroundColor = palette.panel
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            content.addArrangedSubview(field)
        }
        if actions.isEmpty { actions.append(ReaderAlertAction(title: L("닫기"), style: .cancel)) }
        // Many voice choices belong in the scrollable body; keep Close visible.
        let choices = actions.count > 2 ? actions.filter { $0.style != .cancel } : []
        for action in choices { content.addArrangedSubview(button(action)) }
        root.addArrangedSubview(scroll(content))
        let line = UIView(); line.backgroundColor = palette.secondary.withAlphaComponent(0.16)
        line.heightAnchor.constraint(equalToConstant: 0.7).isActive = true; root.addArrangedSubview(line)
        let footer = UIStackView()
        let footerActions = choices.isEmpty ? actions : actions.filter { $0.style == .cancel }
        footer.axis = footerActions.count > 2 || traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        footer.distribution = .fillEqually; footer.spacing = 8
        footer.isLayoutMarginsRelativeArrangement = true
        footer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        for action in footerActions { footer.addArrangedSubview(button(action)) }
        let footerScroll = scroll(footer)
        footerScroll.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.45).isActive = true
        root.addArrangedSubview(footerScroll)
    }

    private func scroll(_ content: UIView) -> UIScrollView {
        let scroll = UIScrollView(); scroll.alwaysBounceVertical = false
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        let natural = scroll.heightAnchor.constraint(equalTo: content.heightAnchor)
        natural.priority = .defaultHigh; natural.isActive = true
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return scroll
    }

    private func button(_ action: ReaderAlertAction) -> UIButton {
        let result = UIButton(type: .system)
        result.setTitle(action.title, for: .normal)
        result.setTitleColor(action.style == .destructive ? .systemRed : palette.accent, for: .normal)
        result.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 14, weight: .semibold))
        result.titleLabel?.adjustsFontForContentSizeCategory = true
        result.titleLabel?.numberOfLines = 0; result.titleLabel?.textAlignment = .center
        result.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        result.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        result.addAction(UIAction { [weak self] _ in self?.finish(action) }, for: .touchUpInside)
        return result
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let field = textFields?.first { field.becomeFirstResponder() }
        UIAccessibility.post(notification: .screenChanged, argument: (textFields?.first as UIView?) ?? headingLabel)
    }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancel))]
    }
    override func accessibilityPerformEscape() -> Bool { if isDismissible { cancel(); return true }; return false }
    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        if !card.frame.contains(gesture.location(in: view)) { cancel() }
    }
    @objc private func cancel() { if isDismissible { finish(actions.first { $0.style == .cancel }) } }
    private func finish(_ action: ReaderAlertAction?) {
        guard !closing else { return }; closing = true
        view.endEditing(true)
        dismiss(animated: true) { [self] in
            if let action { action.handler?(action) }
            group?.finished(self)
        }
    }

    private static let queues = NSMapTable<UIViewController, QueueGroup>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private static var activationObserver: NSObjectProtocol?
    private static func observeActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { _ in Task { @MainActor in
                for group in queues.objectEnumerator()?.allObjects as? [QueueGroup] ?? [] { group.advance() }
            } }
    }
    static func dismissAll(presentedBy owner: UIViewController) {
        // Include alerts owned by a reader's tools/settings page, not only its root.
        for group in queues.objectEnumerator()?.allObjects as? [QueueGroup] ?? [] {
            guard let presenter = group.owner else { continue }
            var ancestor: UIViewController? = presenter
            var belongs = false
            while let current = ancestor {
                if current === owner || current === owner.navigationController { belongs = true; break }
                ancestor = current.parent ?? current.presentingViewController
            }
            guard belongs else { continue }
            queues.removeObject(forKey: presenter); group.items.removeAll()
            let active = group.active; group.active = nil
            active?.closing = true; active?.dismiss(animated: false)
        }
    }
    private final class QueueGroup {
        weak var owner: UIViewController?
        var items: [ReaderAlertController] = []
        var active: ReaderAlertController?
        init(owner: UIViewController) { self.owner = owner }
        func advance() {
            guard active == nil, !items.isEmpty, UIApplication.shared.applicationState == .active else { return }
            guard let owner, owner.viewIfLoaded?.window != nil, !owner.isBeingDismissed else { items.removeAll(); return }
            if let presented = owner.presentedViewController {
                if presented.isBeingDismissed {
                    // Wait for a settings/tools dismissal before presenting a queued notice.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.advance() }
                }
                return
            }
            let next = items.removeFirst(); active = next; owner.present(next, animated: true)
        }
        func finished(_ alert: ReaderAlertController) { if active === alert { active = nil; advance() } }
    }
}
