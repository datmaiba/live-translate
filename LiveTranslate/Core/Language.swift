import Foundation

enum Lang: String, Codable, CaseIterable, Identifiable {
    case vi
    case en

    var id: String { rawValue }
    var bcp47: String { self == .vi ? "vi-VN" : "en-US" }
    var locale: Locale { Locale(identifier: bcp47) }
    var shortLabel: String { self == .vi ? "VI" : "EN" }
    var name: String { self == .vi ? "Tiếng Việt" : "English" }
    var flag: String { self == .vi ? "🇻🇳" : "🇬🇧" }
    var other: Lang { self == .vi ? .en : .vi }
}

struct Direction: Codable, Equatable, Hashable {
    var source: Lang

    var target: Lang { source.other }

    static let viToEn = Direction(source: .vi)
    static let enToVi = Direction(source: .en)

    func swapped() -> Direction { Direction(source: target) }

    var label: String { "\(source.shortLabel) → \(target.shortLabel)" }
}
