import Foundation

public enum ProfileStoreError: LocalizedError, Equatable {
    case invalidName
    case alreadyExists(String)
    case notCustomizable

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a name made of letters or numbers."
        case .alreadyExists(let folder):
            return "A profile folder named “\(folder)” already exists."
        case .notCustomizable:
            return "The default profile can't be deleted."
        }
    }
}

/// Discovers, creates and labels profiles.
///
/// Profiles are plain folders next to Claude's own data folder:
/// `~/Library/Application Support/Claude-<Name>`. Anything matching that pattern shows up,
/// including folders made by hand. Names and colors live in a small JSON file owned by this
/// app, so Claude's folders are never written to.
public final class ProfileStore {
    public static let folderPrefix = "Claude-"

    public let supportDirectory: URL
    public let metadataURL: URL
    private let fileManager: FileManager

    public init(supportDirectory: URL, metadataURL: URL, fileManager: FileManager = .default) {
        self.supportDirectory = supportDirectory
        self.metadataURL = metadataURL
        self.fileManager = fileManager
    }

    /// The real locations: `~/Library/Application Support` and this app's own folder inside it.
    public convenience init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let metadata = support
            .appendingPathComponent("Claude Profiles", isDirectory: true)
            .appendingPathComponent("profiles.json")
        self.init(supportDirectory: support, metadataURL: metadata)
    }

    // MARK: Reading

    /// Default profile first, then custom profiles sorted by name.
    public func profiles() -> [Profile] {
        let metadata = loadMetadata()
        let defaultEntry = metadata[Profile.defaultID]
        let stock = Profile(
            id: Profile.defaultID,
            name: defaultEntry?.name ?? Profile.defaultName,
            color: defaultEntry?.color ?? .graphite,
            dataDirectory: nil
        )

        let entries = (try? fileManager.contentsOfDirectory(
            at: supportDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let custom = entries.compactMap { url -> Profile? in
            let folder = url.lastPathComponent
            guard folder.hasPrefix(Self.folderPrefix), folder.count > Self.folderPrefix.count,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return nil }
            let suffix = String(folder.dropFirst(Self.folderPrefix.count))
            let entry = metadata[folder]
            return Profile(
                id: folder,
                name: entry?.name ?? ProfileSlug.displayName(fromFolderSuffix: suffix),
                color: entry?.color ?? ProfileColor.automatic(for: folder),
                dataDirectory: url.standardizedFileURL
            )
        }
        .sorted { a, b in
            let byName = a.name.localizedCaseInsensitiveCompare(b.name)
            return byName == .orderedSame ? a.id < b.id : byName == .orderedAscending
        }

        return [stock] + custom
    }

    /// Looks a profile up by the data directory Claude was launched with.
    public func profile(forDataDirectory directory: URL?) -> Profile? {
        guard let directory else { return profiles().first }
        let path = directory.standardizedFileURL.path
        return profiles().first { $0.dataDirectory?.path == path }
    }

    // MARK: Writing

    @discardableResult
    public func createProfile(named rawName: String, color: ProfileColor? = nil) throws -> Profile {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slug = ProfileSlug.make(from: name) else { throw ProfileStoreError.invalidName }

        let folder = Self.folderPrefix + slug
        let directory = supportDirectory.appendingPathComponent(folder, isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) {
            throw ProfileStoreError.alreadyExists(folder)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let chosen = color ?? ProfileColor.automatic(for: folder)
        var metadata = loadMetadata()
        metadata[folder] = Metadata(name: name, color: chosen)
        try saveMetadata(metadata)

        return Profile(id: folder, name: name, color: chosen, dataDirectory: directory.standardizedFileURL)
    }

    /// Changes the display name only; the folder on disk keeps its name so Claude is never disturbed.
    public func rename(_ profile: Profile, to rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProfileSlug.make(from: name) != nil else { throw ProfileStoreError.invalidName }
        try update(profile.id) { $0.name = name }
    }

    public func setColor(_ color: ProfileColor, for profile: Profile) throws {
        try update(profile.id) { $0.color = color }
    }

    /// Moves the profile's folder to the Trash. Signs that account out as far as this Mac is concerned.
    public func trash(_ profile: Profile) throws {
        guard let directory = profile.dataDirectory else { throw ProfileStoreError.notCustomizable }
        try fileManager.trashItem(at: directory, resultingItemURL: nil)
        var metadata = loadMetadata()
        metadata.removeValue(forKey: profile.id)
        try saveMetadata(metadata)
    }

    // MARK: Metadata file

    private struct Metadata: Codable {
        var name: String?
        var color: ProfileColor?
    }

    private func loadMetadata() -> [String: Metadata] {
        guard let data = try? Data(contentsOf: metadataURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Metadata].self, from: data)) ?? [:]
    }

    private func saveMetadata(_ metadata: [String: Metadata]) throws {
        try fileManager.createDirectory(
            at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    private func update(_ id: String, _ change: (inout Metadata) -> Void) throws {
        var metadata = loadMetadata()
        var entry = metadata[id] ?? Metadata()
        change(&entry)
        metadata[id] = entry
        try saveMetadata(metadata)
    }
}
