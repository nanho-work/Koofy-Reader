import CryptoKit
import Foundation
import ReadiumNavigator
import ReadiumShared

/// Installs the bundled catalog in private storage. The navigator consumes local
/// files, so a future downloader can supply fonts through the same interface.
final class ReaderFonts {
    static let ids = ["default", "maplestory", "hakgyoansim-siganpyo"]
    static let labels = ["기본", "메이플스토리", "학교안심 시간표"]

    private struct Catalog: Decodable {
        let version: Int
        let families: [Family]
    }
    private struct Family: Decodable {
        let id: String
        let label: String
        let cssFamily: String
        let faces: [Face]
    }
    private struct Face: Decodable {
        let file: String
        let weight: Int
        let sha256: String
    }
    static func isValidId(_ id: String?) -> Bool {
        let value = id ?? "default"
        return ids.contains(value) || value.range(of: "^remote_[a-f0-9]{32}$", options: .regularExpression) != nil
    }
    let optionIds: [String]
    let optionLabels: [String]
    let declarations: [AnyHTMLFontFamilyDeclaration]
    private let families: [String: FontFamily]

    init(directory: URL? = nil, downloadedDirectory: URL? = nil) throws {
        let bundle = Bundle(for: ReaderFonts.self)
        guard let url = bundle.url(forResource: "KoofyReaderAssets", withExtension: "bundle"),
              let resources = Bundle(url: url),
              let catalogURL = resources.url(forResource: "catalog", withExtension: "json") else {
            throw Self.invalidFont()
        }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
        guard catalog.version == 1 else { throw Self.invalidFont() }
        let directory = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("KoofyReader/fonts/v1", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var loadedFamilies = Dictionary(uniqueKeysWithValues: catalog.families.map { ($0.id, FontFamily(rawValue: $0.cssFamily)) })
        var loadedDeclarations = try catalog.families.map { family in
            let faces: [CSSFontFace] = try family.faces.map { face in
                guard face.sha256.count == 64, face.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                      let weight = CSSStandardFontWeight(rawValue: face.weight) else { throw Self.invalidFont() }
                let target = directory.appendingPathComponent(face.sha256).appendingPathExtension("otf")
                if (try? Data(contentsOf: target)).map(Self.digest) != face.sha256 {
                    guard let source = resources.url(forResource: face.file, withExtension: nil) else { throw Self.invalidFont() }
                    let bytes = try Data(contentsOf: source)
                    guard bytes.prefix(4) == Data("OTTO".utf8), Self.digest(bytes) == face.sha256 else { throw Self.invalidFont() }
                    try bytes.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                guard let file = FileURL(url: target) else { throw Self.invalidFont() }
                return CSSFontFace(file: file, style: .normal, weight: .standard(weight))
            }
            return CSSFontFamilyDeclaration(fontFamily: FontFamily(rawValue: family.cssFamily),
                alternates: [.sansSerif], fontFaces: faces).eraseToAnyHTMLFontFamilyDeclaration()
        }
        var loadedIds = ["default"] + catalog.families.map(\.id)
        var loadedLabels = ["기본"] + catalog.families.map(\.label)
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let remoteDirectory = downloadedDirectory ?? support.appendingPathComponent("cloud_reader/fonts", isDirectory: true)
        let manifestURL = remoteDirectory.appendingPathComponent("catalog.json")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: manifestURL.path),
           let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576,
           let data = try? Data(contentsOf: manifestURL),
           let remote = try? JSONDecoder().decode(Catalog.self, from: data), remote.version == 1 {
            for family in remote.families {
                guard family.id.hasPrefix("remote_"), Self.isValidId(family.id),
                      !loadedIds.contains(family.id), !family.label.isEmpty, family.label.count <= 160,
                      (1...9).contains(family.faces.count) else { continue }
                let alias = "KoofyRemote_" + family.id.dropFirst(7)
                guard let faces = try? family.faces.map({ face -> CSSFontFace in
                    guard face.sha256.count == 64, face.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                          [face.sha256 + ".otf", face.sha256 + ".ttf"].contains(face.file),
                          let weight = CSSStandardFontWeight(rawValue: face.weight) else { throw Self.invalidFont() }
                    let target = remoteDirectory.appendingPathComponent(face.file)
                    guard target.resolvingSymlinksInPath().deletingLastPathComponent() == remoteDirectory.resolvingSymlinksInPath(),
                          let size = try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber,
                          (12...10_485_760).contains(size.intValue) else { throw Self.invalidFont() }
                    let bytes = try Data(contentsOf: target)
                    guard Self.digest(bytes) == face.sha256,
                          bytes.prefix(4) == Data("OTTO".utf8) || bytes.prefix(4) == Data([0, 1, 0, 0]),
                          let file = FileURL(url: target) else { throw Self.invalidFont() }
                    return CSSFontFace(file: file, style: .normal, weight: .standard(weight))
                }) else { continue }
                loadedIds.append(family.id); loadedLabels.append(family.label)
                loadedFamilies[family.id] = FontFamily(rawValue: alias)
                loadedDeclarations.append(CSSFontFamilyDeclaration(fontFamily: FontFamily(rawValue: alias),
                    alternates: [.sansSerif], fontFaces: faces).eraseToAnyHTMLFontFamilyDeclaration())
            }
        }
        families = loadedFamilies; declarations = loadedDeclarations
        optionIds = loadedIds; optionLabels = loadedLabels
    }

    func family(_ id: String?) -> FontFamily? { id.flatMap { families[$0] } }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func invalidFont() -> Error {
        PigeonError(code: "font_install_failed", message: "글꼴 파일을 준비하지 못했습니다. 앱을 다시 실행해 주세요.", details: nil)
    }
}
