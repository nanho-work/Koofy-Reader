import Foundation
import ReadiumShared

struct SpeechStart {
    let locator: Locator
    let skip: Int
}

func speechStart(publication: Publication, target: Locator) async throws -> SpeechStart {
    var locator = target
    if locator.locations.otherLocations["cssSelector"] == nil, let id = locator.locations.fragments.first {
        let escaped = id.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        locator.locations.otherLocations["cssSelector"] = .string("[id=\"\(escaped)\"]")
    }
    if let ordinal = locator.locations.otherLocations["koofySpeechOrdinal"]?.integer, ordinal >= 0 {
        return SpeechStart(locator: locator, skip: min(ordinal, 100_000))
    }
    guard target.text.highlight?.isEmpty == false,
          let iterator = publication.content(from: locator)?.iterator(),
          let element = try await iterator.next() as? TextContentElement else { return SpeechStart(locator: locator, skip: 0) }
    var skip = 0
    for segment in element.segments {
        let tokenize = makeDefaultTextTokenizer(unit: .sentence, language: segment.language ?? Language(code: .bcp47("ko")))
        let ranges = try tokenize(segment.text)
        if let position = speechQuoteOffset(text: segment.text, before: target.text.before, highlight: target.text.highlight, after: target.text.after) {
            let index = ranges.firstIndex { compactSpeech(String(segment.text[..<$0.upperBound])).count > position }
            return SpeechStart(locator: locator, skip: skip + (index ?? max(0, ranges.count - 1)))
        }
        skip += ranges.count
    }
    throw NSError(domain: "KoofySpeech", code: 2, userInfo: [NSLocalizedDescriptionKey: "읽던 문장을 찾지 못했습니다. 본문 위치를 옮긴 뒤 다시 재생해 주세요."])
}
private func compactSpeech(_ value: String) -> String { String(value.filter { !$0.isWhitespace }) }
private func speechQuoteOffset(text: String, before: String?, highlight: String?, after: String?) -> Int? {
    let source = compactSpeech(text), head = compactSpeech(before ?? ""), quote = compactSpeech(highlight ?? ""), tail = compactSpeech(after ?? "")
    if quote.isEmpty { return 0 }
    func index(_ needle: String) -> Int? { source.range(of: needle, options: tail.isEmpty && !head.isEmpty ? .backwards : []).map { source.distance(from: source.startIndex, to: $0.lowerBound) } }
    if let value = index(head + quote + tail) { return value + head.count }
    if !head.isEmpty, let value = index(head + quote) { return value + head.count }
    if !tail.isEmpty, let value = index(quote + tail) { return value }
    if quote.count > 4 { return index(quote) }
    return nil
}
