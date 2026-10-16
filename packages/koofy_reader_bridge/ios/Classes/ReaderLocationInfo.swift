import Foundation
import ReadiumShared

/// Content positions stay independent of screen pagination and are presentation only.
struct ReaderLocationInfo {
    private var positions: [Locator]
    init(_ all: [Locator] = []) { positions = all.filter { !isReaderDisplayCover($0) } }
    func index(_ locator: Locator) -> Int? {
        guard !positions.isEmpty, !isReaderDisplayCover(locator) else { return nil }
        if let position = locator.locations.position,
           let index = positions.firstIndex(where: { $0.locations.position == position && $0.href.string.components(separatedBy: "#")[0] == locator.href.string.components(separatedBy: "#")[0] }) { return index + 1 }
        let resource = locator.href.string.components(separatedBy: "#")[0]
        let candidates = positions.enumerated().filter { $0.element.href.string.components(separatedBy: "#")[0] == resource }
        guard let first = candidates.first else { return nil }
        let found = candidates.last { ($0.element.locations.progression ?? 0) <= (locator.locations.progression ?? 0) } ?? first
        return found.offset + 1
    }
    func progress(_ locator: Locator, approximate: Bool = false) -> String? {
        let estimate = index(locator).map { positions[$0 - 1].locations.totalProgression ?? Double($0 - 1) / Double(positions.count) }
        guard let value = locator.locations.totalProgression ?? estimate, value.isFinite else { return nil }
        let label = "\(Int(min(1, max(0, value)) * 100))%"
        return approximate || locator.locations.totalProgression?.isFinite != true ? L("약 {0}", label) : label
    }
    // Preserve legacy settings in storage; never display content-position numbers.
    func detail(_ locator: Locator, approximate: Bool = false) -> String { progress(locator, approximate: approximate) ?? "" }
    func footer(_ locator: Locator, mode: String?) -> String { mode == "none" ? "" : progress(locator) ?? "" }
}
