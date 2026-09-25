import CryptoKit
import Foundation

/// Recovery journal only. Flutter remains the sole owner of the domain database.
/// All accesses occur on the bridge's main queue, so acknowledgements cannot race writes.
final class ReaderCheckpointStore {
    private let directory: URL

    init(directory: URL? = nil) throws {
        self.directory = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("KoofyReader/checkpoints", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func write(_ event: ReaderEvent) throws {
        let url = fileURL(event.sessionId)
        let identity = try JSONSerialization.data(withJSONObject: ["publicationId": event.publicationId])
        try identity.write(to: url.appendingPathExtension("identity"), options: .atomic)
        let bytes = try JSONEncoder().encode(Checkpoint(event))
        if let previous = try? Data(contentsOf: url),
           (try? JSONDecoder().decode(Checkpoint.self, from: previous)) != nil {
            try previous.write(to: url.appendingPathExtension("previous"), options: .atomic)
        }
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
    }

    func pending() throws -> [ReaderEvent] {
        let paths = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        let roots = Set(paths.filter { $0.pathExtension == "json" || $0.pathExtension == "previous" }
            .map { $0.pathExtension == "previous" ? $0.deletingPathExtension() : $0 })
        return roots.compactMap { url -> ReaderEvent? in
            do { return try read(url)?.event }
            catch {
                let publication = [url.appendingPathExtension("identity"), url].compactMap { candidate -> String? in
                    guard let data = try? Data(contentsOf: candidate),
                          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let id = json["publicationId"] as? String, !id.isEmpty else { return nil }
                    return id
                }.first ?? ""
                return ReaderEvent(protocolVersion: 1, sessionId: url.lastPathComponent,
                    sessionGeneration: 0, publicationId: publication, contentRevision: "",
                    sequence: 0, kind: "recoveryIssue", errorCode: "checkpoint_corrupt",
                    message: "읽기 복구 기록이 손상되었습니다. 원본 기록은 보존되어 있습니다.")
            }
        }.sorted {
            ($0.sessionGeneration, $0.sequence) < ($1.sessionGeneration, $1.sequence)
        }
    }

    func acknowledge(sessionId: String, sequence: Int64) throws {
        let url = fileURL(sessionId)
        guard let record = try read(url), record.event.sessionId == sessionId,
              record.event.sequence == sequence else { return }
        // Remove the fallback before the acknowledged record, preventing an old
        // fallback from being recovered after a process interruption here.
        let backup = url.appendingPathExtension("previous")
        if FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.removeItem(at: backup)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let identity = url.appendingPathExtension("identity")
        if FileManager.default.fileExists(atPath: identity.path) {
            try FileManager.default.removeItem(at: identity)
        }
    }

    private func fileURL(_ sessionId: String) -> URL {
        let digest = SHA256.hash(data: Data(sessionId.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }

    private func read(_ url: URL) throws -> Checkpoint? {
        let candidates = [url, url.appendingPathExtension("previous")]
        var lastError: Error?
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            do {
                let record = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: candidate))
                guard record.version == 1, record.protocolVersion == 1,
                      record.sequence > 0, record.sessionGeneration > 0 else {
                    throw PigeonError(code: "checkpoint_corrupt", message: "읽기 복구 기록의 버전 또는 순서가 잘못되었습니다.", details: nil)
                }
                return record
            } catch { lastError = error }
        }
        if let lastError { throw lastError }
        return nil
    }
}

private struct Checkpoint: Codable {
    var version = 1
    let protocolVersion: Int64
    let sessionId: String
    let sessionGeneration: Int64
    let publicationId: String
    let contentRevision: String
    let sequence: Int64
    let kind: String
    let locatorJson: String?
    let bookmarksJson: String?
    let fontScale: Double?
    let columnCount: Int64?
    let scroll: Bool?
    let theme: String?
    let pageTurnStyle: String?
    let fontId: String?
    let lineHeight: Double?
    let paragraphSpacing: Double?
    let pageMargins: Double?
    let errorCode: String?
    let message: String?

    init(_ event: ReaderEvent) {
        protocolVersion = event.protocolVersion
        sessionId = event.sessionId
        sessionGeneration = event.sessionGeneration
        publicationId = event.publicationId
        contentRevision = event.contentRevision
        sequence = event.sequence
        kind = event.kind
        locatorJson = event.locatorJson
        bookmarksJson = event.bookmarksJson
        fontScale = event.preferences?.fontScale
        columnCount = event.preferences?.columnCount
        scroll = event.preferences?.scroll
        theme = event.preferences?.theme
        pageTurnStyle = event.preferences?.pageTurnStyle
        fontId = event.preferences?.fontId
        lineHeight = event.preferences?.lineHeight
        paragraphSpacing = event.preferences?.paragraphSpacing
        pageMargins = event.preferences?.pageMargins
        errorCode = event.errorCode
        message = event.message
    }

    var event: ReaderEvent {
        var preferences: ReaderPreferences?
        if let fontScale, let columnCount, let scroll, let theme {
            preferences = ReaderPreferences(fontScale: fontScale, columnCount: columnCount, scroll: scroll,
                theme: theme, pageTurnStyle: pageTurnStyle, fontId: fontId,
                lineHeight: lineHeight, paragraphSpacing: paragraphSpacing, pageMargins: pageMargins)
        }
        return ReaderEvent(protocolVersion: protocolVersion, sessionId: sessionId,
            sessionGeneration: sessionGeneration, publicationId: publicationId,
            contentRevision: contentRevision, sequence: sequence, kind: kind,
            locatorJson: locatorJson, preferences: preferences, errorCode: errorCode, message: message, bookmarksJson: bookmarksJson)
    }
}
