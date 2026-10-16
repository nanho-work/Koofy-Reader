import UIKit
import ReadiumShared

struct ReaderBookmark {
    let id: String
    let label: String
    let locator: Locator
    static func decode(_ json: String) throws -> [ReaderBookmark] {
        guard let rows = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]], rows.count <= 100 else {
            throw NSError(domain: "ReaderBookmarks", code: 1)
        }
        return try rows.map { row in
            guard let id = row["id"] as? String, let label = row["label"] as? String,
                  let location = row["locator"] as? [String: Any] else { throw NSError(domain: "ReaderBookmarks", code: 2) }
            let data = try JSONSerialization.data(withJSONObject: location)
            return ReaderBookmark(id: id, label: label, locator: try Locator(jsonString: String(decoding: data, as: UTF8.self)))
        }
    }
    static func encode(_ rows: [ReaderBookmark]) throws -> String {
        let objects: [[String: Any]] = try rows.map { ["id": $0.id, "label": $0.label,
            "locator": try JSONSerialization.jsonObject(with: Data($0.locator.jsonString().utf8))] }
        let data = try JSONSerialization.data(withJSONObject: objects)
        guard data.count <= 512 * 1024 else { throw NSError(domain: "ReaderBookmarks", code: 3) }
        return String(decoding: data, as: UTF8.self)
    }
    static func snippet(_ locator: Locator) -> String {
        let text = locator.text
        let excerpt = [text.before, text.highlight, text.after].compactMap { $0 }.joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return String((excerpt.isEmpty ? locator.title ?? L("저장한 본문 위치") : excerpt).prefix(180))
    }
    static func sameAnchor(_ a: Locator, _ b: Locator) -> Bool {
        guard a.href.string.components(separatedBy: "#")[0] == b.href.string.components(separatedBy: "#")[0] else { return false }
        guard let left = try? JSONSerialization.jsonObject(with: Data(a.jsonString().utf8)) as? [String: Any],
              let right = try? JSONSerialization.jsonObject(with: Data(b.jsonString().utf8)) as? [String: Any] else { return a == b }
        let x = (left["locations"] as? [String: Any])?["koofyText"] as? [String: Any]
        let y = (right["locations"] as? [String: Any])?["koofyText"] as? [String: Any]
        if x != nil || y != nil {
            guard let x, let y else { return false }
            return NSDictionary(dictionary: x).isEqual(NSDictionary(dictionary: y))
        }
        return NSDictionary(dictionary: left).isEqual(NSDictionary(dictionary: right))
    }
    static func label(_ text: String) -> String {
        var result = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if result.utf16.count + String(character).utf16.count > 300 { break }
            result.append(character)
        }
        return result.isEmpty ? L("책갈피") : result
    }
}

class ReaderToolTableController: UITableViewController {
    var palette = ReaderPalette.forTheme("sepia")
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = palette.background
        tableView.tintColor = palette.accent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = palette.background
        appearance.titleTextAttributes = [.foregroundColor: palette.foreground]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = palette.accent
    }
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = palette.background
        cell.textLabel?.textColor = cell.isUserInteractionEnabled ? palette.foreground : palette.secondary
        cell.detailTextLabel?.textColor = palette.secondary
    }
}

final class ReaderBookmarksViewController: ReaderToolTableController {
    private var rows: [ReaderBookmark]
    private let current: Locator?
    private let detail: (Locator) -> String
    private let save: ([ReaderBookmark]) throws -> Void
    private let jump: (Locator) -> Void
    private var undo: (ReaderBookmark, Int)?
    private var errorMessage: String?
    private var displayed: [ReaderBookmark] { Array(rows.reversed()) }
    init(rows: [ReaderBookmark], current: Locator? = nil, detail: @escaping (Locator) -> String = { _ in "" }, save: @escaping ([ReaderBookmark]) throws -> Void, jump: @escaping (Locator) -> Void) {
        self.rows = rows; self.current = current; self.detail = detail; self.save = save; self.jump = jump
        super.init(style: .plain); title = L("책갈피")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: L("닫기"), style: .plain, target: self, action: #selector(close))
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 130
    }
    @objc private func close() { dismiss(animated: true) }
    private func message(_ text: String) {
        errorMessage = text; tableView.reloadData()
        UIAccessibility.post(notification: .announcement, argument: text)
    }
    private func persist(_ next: [ReaderBookmark], after: (() -> Void)? = nil) {
        do { try save(next); rows = next; errorMessage = nil; after?(); tableView.reloadData() }
        catch { message(L("저장하지 못했습니다. 다시 시도해 주세요.")) }
    }
    private func remove(_ id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        var next = rows; let removed = next.remove(at: index)
        persist(next, after: { self.undo = (removed, index) })
    }
    private func restore() {
        guard let (row, index) = undo else { return }
        if rows.contains(where: { ReaderBookmark.sameAnchor($0.locator, row.locator) }) { undo = nil; tableView.reloadData(); return }
        guard rows.count < 100 else { message(L("책갈피는 책마다 100개까지 저장할 수 있습니다.")); return }
        var next = rows; next.insert(row, at: min(index, next.count))
        persist(next, after: { self.undo = nil })
    }
    private func toggleCurrent() {
        guard let current, !isReaderDisplayCover(current) else { return }
        if let row = rows.first(where: { ReaderBookmark.sameAnchor($0.locator, current) }) { remove(row.id); return }
        guard rows.count < 100 else { message(L("책갈피는 책마다 100개까지 저장할 수 있습니다.")); return }
        let added = ReaderBookmark(id: UUID().uuidString, label: ReaderBookmark.label(ReaderBookmark.snippet(current)), locator: current)
        persist(rows + [added], after: {
            if let previous = self.undo, ReaderBookmark.sameAnchor(previous.0.locator, current) { self.undo = nil }
        })
    }
    private func rename(_ id: String) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        let editor = UIAlertController(title: L("책갈피 이름"), message: nil, preferredStyle: .alert)
        editor.addTextField { $0.text = row.label }
        editor.addAction(UIAlertAction(title: L("취소"), style: .cancel))
        editor.addAction(UIAlertAction(title: L("저장"), style: .default) { [weak self, weak editor] _ in
            guard let self, let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
            var next = self.rows
            next[index] = ReaderBookmark(id: row.id, label: ReaderBookmark.label(editor?.textFields?.first?.text ?? ""), locator: row.locator)
            self.persist(next)
        })
        present(editor, animated: true)
    }
    private func open(_ locator: Locator) { dismiss(animated: true) { self.jump(locator) } }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 + (undo == nil ? 0 : 1) + (errorMessage == nil ? 0 : 1) : max(1, rows.count) }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 1 ? L("책갈피 {0}개", String(rows.count)) : nil }
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt path: IndexPath) {
        super.tableView(tableView, willDisplay: cell, forRowAt: path)
        if path.section == 0 && cell.isUserInteractionEnabled { cell.textLabel?.textColor = palette.accent }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = palette.background; cell.textLabel?.textColor = palette.foreground
        cell.textLabel?.font = .preferredFont(forTextStyle: .body); cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        if path.section == 0 {
            if path.row > 0 {
                if path.row == 1, let errorMessage { cell.textLabel?.text = errorMessage; cell.isUserInteractionEnabled = false; cell.selectionStyle = .none; return cell }
                cell.textLabel?.text = L("삭제 실행 취소"); cell.accessibilityIdentifier = "bookmark-undo"
            } else {
                let saved = current.map { target in rows.contains { ReaderBookmark.sameAnchor($0.locator, target) } } ?? false
                cell.textLabel?.text = saved ? L("이곳의 책갈피 해제") : L("이곳에 책갈피 추가")
                cell.isUserInteractionEnabled = current != nil && !isReaderDisplayCover(current)
                cell.accessibilityIdentifier = "bookmark-toggle"
                if !cell.isUserInteractionEnabled { cell.textLabel?.textColor = palette.secondary }
            }
            cell.accessibilityTraits = .button; return cell
        }
        guard !rows.isEmpty else { cell.textLabel?.text = L("저장한 책갈피가 없습니다."); cell.textLabel?.textColor = palette.secondary; cell.selectionStyle = .none; return cell }
        let row = displayed[path.row]
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 6
        func label(_ text: String, secondary: Bool) {
            let value = UILabel(); value.text = text; value.numberOfLines = secondary ? 2 : 3
            value.font = .preferredFont(forTextStyle: secondary ? .caption1 : .body); value.adjustsFontForContentSizeCategory = true
            value.textColor = secondary ? palette.secondary : palette.foreground; stack.addArrangedSubview(value)
        }
        label(row.label, secondary: false)
        let excerpt = ReaderBookmark.snippet(row.locator)
        if excerpt != row.label { label(excerpt, secondary: true) }
        let metadata = detail(row.locator)
        if !metadata.isEmpty { label(metadata, secondary: true) }
        let actions = UIStackView(); actions.distribution = .fillEqually; actions.spacing = 4
        func button(_ title: String, id: String, destructive: Bool = false, perform: @escaping () -> Void) {
            let value = UIButton(type: .system)
            var config = UIButton.Configuration.plain(); config.title = title; config.baseForegroundColor = destructive ? .systemRed : palette.accent
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var result = attributes; result.font = UIFont.preferredFont(forTextStyle: .footnote); return result }
            value.configuration = config; value.titleLabel?.numberOfLines = 0; value.titleLabel?.adjustsFontForContentSizeCategory = true
            value.accessibilityIdentifier = id; value.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            value.addAction(UIAction { _ in perform() }, for: .touchUpInside); actions.addArrangedSubview(value)
        }
        button(L("이동"), id: "bookmark-open-" + row.id) { [weak self] in self?.open(row.locator) }
        button(L("이름 변경"), id: "bookmark-rename-" + row.id) { [weak self] in self?.rename(row.id) }
        button(L("삭제"), id: "bookmark-delete-" + row.id, destructive: true) { [weak self] in self?.remove(row.id) }
        stack.addArrangedSubview(actions); stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)])
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        if path.section == 0 {
            if path.row == 0 { toggleCurrent() }
            else if !(path.row == 1 && errorMessage != nil) { restore() }
            return
        }
        if !rows.isEmpty { open(displayed[path.row].locator) }
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt path: IndexPath) {
        if editingStyle == .delete && path.section == 1 && !rows.isEmpty { remove(displayed[path.row].id) }
    }
    override func tableView(_ tableView: UITableView, canEditRowAt path: IndexPath) -> Bool { path.section == 1 && !rows.isEmpty }
}

final class ReaderSearchViewController: ReaderToolTableController, UISearchBarDelegate {
    private let publication: Publication
    private let jump: (Locator) -> Void
    private let searchBar = UISearchBar()
    private let more = UIButton(type: .system)
    private var rows: [Locator] = []
    private var iterator: SearchIterator?
    private var task: Task<Void, Never>?
    private var serial = 0
    init(publication: Publication, jump: @escaping (Locator) -> Void) {
        self.publication = publication; self.jump = jump
        super.init(style: .plain); title = L("본문 검색")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        searchBar.barTintColor = palette.background; searchBar.tintColor = palette.accent
        searchBar.searchTextField.textColor = palette.foreground
        more.tintColor = palette.accent
        searchBar.placeholder = L("단어 또는 문장 검색"); searchBar.delegate = self; searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar
        more.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        more.setTitle(L("검색어를 입력해 주세요"), for: .normal); more.isEnabled = false
        more.addTarget(self, action: #selector(loadMore), for: .touchUpInside)
        tableView.tableFooterView = more
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        tableView.keyboardDismissMode = .onDrag
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); serial += 1; task?.cancel(); iterator = nil
    }
    @objc private func close() { dismiss(animated: true) }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder(); load(reset: true) }
    @objc private func loadMore() { load(reset: false) }
    private func load(reset: Bool) {
        let query = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 200 else { more.setTitle(L("검색어를 1~200자로 입력해 주세요"), for: .normal); return }
        serial += 1; let run = serial; task?.cancel()
        if reset { iterator = nil; rows = []; tableView.reloadData() }
        more.isEnabled = false; more.setTitle(L("검색 중…"), for: .normal)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let active: SearchIterator
                if let iterator { active = iterator } else { active = try await publication.search(query: query).get() }
                guard !Task.isCancelled, run == serial else { return }
                iterator = active
                let page = try await active.next().get()
                guard !Task.isCancelled, run == serial else { return }
                rows.append(contentsOf: (page?.locators ?? []).prefix(500 - rows.count))
                tableView.reloadData()
                more.isEnabled = page != nil && rows.count < 500
                more.setTitle(rows.count >= 500 ? L("500개 표시 · 검색어를 더 구체적으로 입력해 주세요") :
                    page != nil ? L("{0}개 찾음 · 더 보기", String(rows.count)) : rows.isEmpty ? L("검색 결과가 없습니다") : L("{0}개 찾음 · 검색 완료", String(rows.count)), for: .normal)
            } catch { if !Task.isCancelled, run == serial { more.setTitle(L("검색 실패 · 다시 검색해 주세요"), for: .normal) } }
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = ReaderBookmark.snippet(rows[indexPath.row]); cell.textLabel?.numberOfLines = 3
        cell.detailTextLabel?.text = rows[indexPath.row].title; cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let location = rows[indexPath.row]; dismiss(animated: true) { self.jump(location) }
    }
}
