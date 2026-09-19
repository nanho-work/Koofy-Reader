import Flutter
import ReadiumShared
import UIKit

public final class KoofyReaderBridgePlugin: NSObject, FlutterPlugin, ReaderHostApi {
    private let registrar: FlutterPluginRegistrar
    private let flutterAPI: ReaderFlutterApi
    private var reader: KoofyReaderViewController?
    private var journal: ReaderCheckpointStore?

    private init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        flutterAPI = ReaderFlutterApi(binaryMessenger: registrar.messenger())
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = KoofyReaderBridgePlugin(registrar: registrar)
        ReaderHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        registrar.publish(instance)
    }

    func openReader(request: ReaderLaunchRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            guard reader == nil else { throw failure("reader_busy", "이미 책을 읽고 있습니다.") }
            guard request.protocolVersion == 1, request.sessionGeneration > 0,
                  !request.sessionId.isEmpty, !request.publicationId.isEmpty,
                  !request.contentRevision.isEmpty else {
                throw failure("invalid_request", "독서 세션 정보가 올바르지 않습니다.")
            }
            try KoofyReaderViewController.validate(request.preferences)
            let path = URL(fileURLWithPath: request.filePath).resolvingSymlinksInPath().standardizedFileURL
            let directories: [FileManager.SearchPathDirectory] = [.documentDirectory, .applicationSupportDirectory]
            let roots = directories.compactMap { directory in
                FileManager.default.urls(for: directory as FileManager.SearchPathDirectory, in: .userDomainMask).first?
                    .resolvingSymlinksInPath().standardizedFileURL.path
            }
            guard path.pathExtension.lowercased() == "epub",
                  roots.contains(where: { path.path.hasPrefix($0 + "/") }),
                  FileManager.default.isReadableFile(atPath: path.path) else {
                throw failure("file_access", "앱에 가져온 EPUB 파일을 찾을 수 없습니다.")
            }
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            guard let presenter = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController, presenter.presentedViewController == nil,
                  presenter.viewIfLoaded?.window != nil else {
                throw failure("host_unavailable", "서재 화면이 준비된 뒤 다시 열어 주세요.")
            }
            let journal = try checkpointStore()
            // Never replay platform restoration arguments. Flutter recovers the
            // journal and allocates a durable generation before calling here.
            let controller = KoofyReaderViewController(request: request, journal: journal) { [weak self] event in
                self?.flutterAPI.onEvent(event: event) { _ in
                    // Callback delivery is NOT an acknowledgement of DB commit.
                }
            }
            controller.onClosed = { [weak self, weak controller] in
                guard self?.reader === controller else { return }
                self?.reader = nil
            }
            reader = controller
            let host = UINavigationController(rootViewController: controller)
            host.modalPresentationStyle = .fullScreen
            host.isModalInPresentation = true
            // Release any Flutter text-input responder before handing input to
            // Readium's own responder chain in the full-screen native host.
            presenter.view.endEditing(true)
            // Finish acceptance after UIKit attaches the host, so a cancelled
            // Flutter launch can immediately close it without racing presentation.
            presenter.present(host, animated: true) { completion(.success(())) }
        } catch { completion(.failure(error)) }
    }

    func closeReader(sessionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        do { try active(sessionId).close(completion: completion) }
        catch { completion(.failure(error)) }
    }

    func goTo(sessionId: String, locatorJson: String, completion: @escaping (Result<Void, Error>) -> Void) {
        do { try active(sessionId).go(to: Locator(jsonString: locatorJson), completion: completion) }
        catch { completion(.failure(error)) }
    }

    func applyPreferences(sessionId: String, preferences: ReaderPreferences, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try KoofyReaderViewController.validate(preferences)
            try active(sessionId).apply(preferences, completion: completion)
        } catch { completion(.failure(error)) }
    }

    func pendingCheckpoints(completion: @escaping (Result<[ReaderEvent], Error>) -> Void) {
        do { completion(.success(try checkpointStore().pending())) }
        catch { completion(.failure(error)) }
    }

    func acknowledgeCheckpoint(sessionId: String, sequence: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try checkpointStore().acknowledge(sessionId: sessionId, sequence: sequence)
            completion(.success(()))
        } catch { completion(.failure(error)) }
    }

    private func active(_ sessionId: String) throws -> KoofyReaderViewController {
        guard let reader, reader.request.sessionId == sessionId else {
            throw failure("stale_session", "이미 종료된 독서 세션입니다.")
        }
        return reader
    }

    private func checkpointStore() throws -> ReaderCheckpointStore {
        if let journal { return journal }
        let journal = try ReaderCheckpointStore()
        self.journal = journal
        return journal
    }
}

func failure(_ code: String, _ message: String) -> PigeonError {
    PigeonError(code: code, message: message, details: nil)
}
