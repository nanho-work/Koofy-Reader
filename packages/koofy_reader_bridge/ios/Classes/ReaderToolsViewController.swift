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
        return String((excerpt.isEmpty ? locator.title ?? "저장한 본문 위치" : excerpt).prefix(180))
    }
    static func label(_ text: String) -> String {
        var result = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if result.utf16.count + String(character).utf16.count > 300 { break }
            result.append(character)
        }
        return result.isEmpty ? "책갈피" : result
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
        cell.textLabel?.textColor = palette.foreground
        cell.detailTextLabel?.textColor = palette.secondary
    }
}

final class ReaderBookmarksViewController: ReaderToolTableController {
    private var rows: [ReaderBookmark]
    private let save: ([ReaderBookmark]) throws -> Void
    private let jump: (Locator) -> Void
    init(rows: [ReaderBookmark], save: @escaping ([ReaderBookmark]) throws -> Void, jump: @escaping (Locator) -> Void) {
        self.rows = rows; self.save = save; self.jump = jump
        super.init(style: .insetGrouped); title = "책갈피"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        tableView.backgroundView = rows.isEmpty ? emptyLabel() : nil
    }
    private func emptyLabel() -> UILabel { let label = UILabel(); label.text = "저장한 책갈피가 없습니다."; label.textAlignment = .center; label.textColor = palette.secondary; return label }
    @objc private func close() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = rows[indexPath.row].label; cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = "눌러서 이동 · 밀어서 삭제"; cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let target = rows[indexPath.row].locator
        dismiss(animated: true) { self.jump(target) }
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        var next = rows; next.remove(at: indexPath.row)
        do { try save(next); rows = next; tableView.reloadData(); tableView.backgroundView = rows.isEmpty ? emptyLabel() : nil }
        catch { let alert = UIAlertController(title: "책갈피를 삭제하지 못했습니다", message: "저장 공간을 확인하고 다시 시도해 주세요.", preferredStyle: .alert); alert.addAction(UIAlertAction(title: "확인", style: .default)); present(alert, animated: true) }
    }
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
        super.init(style: .plain); title = "본문 검색"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        searchBar.barTintColor = palette.background; searchBar.tintColor = palette.accent
        searchBar.searchTextField.textColor = palette.foreground
        more.tintColor = palette.accent
        searchBar.placeholder = "단어 또는 문장 검색"; searchBar.delegate = self; searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar
        more.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        more.setTitle("검색어를 입력해 주세요", for: .normal); more.isEnabled = false
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
        guard !query.isEmpty, query.count <= 200 else { more.setTitle("검색어를 1~200자로 입력해 주세요", for: .normal); return }
        serial += 1; let run = serial; task?.cancel()
        if reset { iterator = nil; rows = []; tableView.reloadData() }
        more.isEnabled = false; more.setTitle("검색 중…", for: .normal)
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
                more.setTitle(rows.count >= 500 ? "500개 표시 · 검색어를 더 구체적으로 입력해 주세요" :
                    page != nil ? "\(rows.count)개 찾음 · 더 보기" : rows.isEmpty ? "검색 결과가 없습니다" : "\(rows.count)개 찾음 · 검색 완료", for: .normal)
            } catch { if !Task.isCancelled, run == serial { more.setTitle("검색 실패 · 다시 검색해 주세요", for: .normal) } }
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
