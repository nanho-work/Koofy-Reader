import Flutter
import UIKit
import UniformTypeIdentifiers

/// Keep document-provider handles until each individual file is copied. Selecting
/// hundreds of iCloud/Drive documents must not eagerly download every document.
final class BookImportChannel: NSObject, UIDocumentPickerDelegate {
    private let channel: FlutterMethodChannel
    private let queue = DispatchQueue(label: "koofy.book-import", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: FlutterResult?
    private var cancelled = false
    private var copying = false
    private let allowed = Set(["txt", "epub", "jpg", "jpeg", "png", "webp"])
    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "koofy_reader/book_import", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(FlutterError(code: "detached", message: "File import closed", details: nil)); return }
            let args = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "pick":
                guard self.pending == nil, !self.copying else { result(FlutterError(code: "busy", message: "File import is active", details: nil)); return }
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
                var host = scene?.windows.first { $0.isKeyWindow }?.rootViewController
                while let presented = host?.presentedViewController { host = presented }
                guard let host, host.viewIfLoaded?.window != nil else { result(FlutterError(code: "host", message: "File picker unavailable", details: nil)); return }
                let epub = UTType(filenameExtension: "epub") ?? .data
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText, epub, .jpeg, .png, UTType(filenameExtension: "webp") ?? .image], asCopy: false)
                picker.allowsMultipleSelection = true
                picker.delegate = self
                self.pending = result
                host.present(picker, animated: true)
            case "copy":
                guard !self.copying else { result(FlutterError(code: "busy", message: "Previous file request is still stopping", details: nil)); return }
                guard let source = args["source"] as? String, let name = args["name"] as? String,
                      (name as NSString).lastPathComponent == name, self.allowed.contains((name as NSString).pathExtension.lowercased()),
                      let limit = args["limit"] as? NSNumber, limit.intValue > 0, limit.intValue <= 40 * 1024 * 1024,
                      !self.copying else { result(FlutterError(code: "invalid_file", message: "Invalid selected file", details: nil)); return }
                self.copying = true
                self.lock.lock(); self.cancelled = false; self.lock.unlock()
                self.queue.async { self.copy(source: source, name: name, limit: limit.intValue, result: result) }
            case "cancel":
                self.lock.lock(); self.cancelled = true; self.lock.unlock(); result(nil)
            case "release": result(nil) // Security scopes are released after every read.
            default: result(FlutterMethodNotImplemented)
            }
        }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let result = pending; pending = nil; result?([])
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let result = pending; pending = nil
        queue.async {
            do {
                let files = try urls.filter { self.allowed.contains($0.pathExtension.lowercased()) }.map { url -> [String: String] in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    return ["name": url.lastPathComponent, "source": bookmark.base64EncodedString()]
                }
                DispatchQueue.main.async { result?(files) }
            } catch { DispatchQueue.main.async { result?(FlutterError(code: "metadata", message: error.localizedDescription, details: nil)) } }
        }
    }
    private func copy(source: String, name: String, limit: Int, result: @escaping FlutterResult) {
        var folder: URL?
        do {
            guard let data = Data(base64Encoded: source) else { throw NSError(domain: "BookImport", code: 1) }
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let fm = FileManager.default
            let root = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("koofy_import/\(UUID().uuidString)", isDirectory: true)
            folder = root
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let temporary = root.appendingPathComponent("download.part")
            var coordinationError: NSError?
            var readError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                do {
                    guard let input = InputStream(url: readable), let output = OutputStream(url: temporary, append: false) else { throw NSError(domain: "BookImport", code: 2) }
                    input.open(); output.open()
                    defer { input.close(); output.close() }
                    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                    var count = 0, reported = 0
                    while true {
                        self.lock.lock(); let stop = self.cancelled; self.lock.unlock()
                        if stop { throw NSError(domain: "BookImportCancelled", code: 1) }
                        let read = input.read(&buffer, maxLength: buffer.count)
                        if read < 0 { throw input.streamError ?? NSError(domain: "BookImport", code: 3) }
                        if read == 0 { break }
                        count += read
                        if count > limit { throw NSError(domain: "BookImportSize", code: 1) }
                        try buffer.withUnsafeBufferPointer { pointer in
                            var written = 0
                            while written < read {
                                let amount = output.write(pointer.baseAddress!.advanced(by: written), maxLength: read - written)
                                if amount <= 0 { throw output.streamError ?? NSError(domain: "BookImport", code: 4) }
                                written += amount
                            }
                        }
                        if count - reported >= 256 * 1024 {
                            reported = count; let received = count
                            DispatchQueue.main.async { self.channel.invokeMethod("progress", arguments: ["bytes": received]) }
                        }
                    }
                    if count == 0 { throw NSError(domain: "BookImportEmpty", code: 1) }
                } catch { readError = error }
            }
            self.lock.lock(); let stopped = self.cancelled; self.lock.unlock()
            if stopped { throw NSError(domain: "BookImportCancelled", code: 1) }
            if let coordinationError { throw coordinationError }
            if let readError { throw readError }
            let target = root.appendingPathComponent(name)
            try fm.moveItem(at: temporary, to: target)
            DispatchQueue.main.async { self.copying = false; result(target.path) }
        } catch {
            if let folder { try? FileManager.default.removeItem(at: folder) }
            DispatchQueue.main.async {
                self.copying = false
                result(FlutterError(code: (error as NSError).domain == "BookImportCancelled" ? "cancelled" : "file_access", message: error.localizedDescription, details: nil))
            }
        }
    }
}
