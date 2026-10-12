import Foundation

/// Accent color used for a profile's badge. Stored by name so the file stays human-readable.
public enum ProfileColor: String, CaseIterable, Codable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite

    /// A stable color for profiles the user hasn't picked one for, derived from `key`
    /// so the same profile always gets the same color.
    public static func automatic(for key: String) -> ProfileColor {
        let palette = allCases.filter { $0 != .graphite }
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

/// One Claude login. The stock profile has no data directory; every other profile owns a
/// folder that Claude is launched with via `--user-data-dir`.
public struct Profile: Hashable, Identifiable, Sendable {
    public static let defaultID = "default"
    public static let defaultName = "Default"

    /// `"default"` for the stock profile, otherwise the data folder's name (e.g. `Claude-Work`).
    public let id: String
    public var name: String
    public var color: ProfileColor
    public let dataDirectory: URL?

    public init(id: String, name: String, color: ProfileColor, dataDirectory: URL?) {
        self.id = id
        self.name = name
        self.color = color
        self.dataDirectory = dataDirectory
    }

    public var isDefault: Bool { dataDirectory == nil }

    /// First character of the name, used on the badge.
    public var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }
}
