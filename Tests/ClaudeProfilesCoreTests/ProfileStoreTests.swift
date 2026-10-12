import XCTest
@testable import ClaudeProfilesCore

final class ProfileStoreTests: XCTestCase {
    private var root: URL!
    private var store: ProfileStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeProfilesTests-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        store = ProfileStore(
            supportDirectory: support,
            metadataURL: root.appendingPathComponent("meta/profiles.json")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAlwaysListsDefaultProfileFirst() {
        let profiles = store.profiles()
        XCTAssertEqual(profiles.map(\.id), [Profile.defaultID])
        XCTAssertEqual(profiles[0].name, "Default")
        XCTAssertTrue(profiles[0].isDefault)
    }

    func testCreateMakesFolderAndRemembersNameAndColor() throws {
        let created = try store.createProfile(named: "Work (ACME)", color: .teal)
        XCTAssertEqual(created.id, "Claude-Work-ACME")
        XCTAssertEqual(created.name, "Work (ACME)")
        XCTAssertEqual(created.color, .teal)

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.dataDirectory!.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        let listed = store.profiles()
        XCTAssertEqual(listed.map(\.name), ["Default", "Work (ACME)"])
        XCTAssertEqual(listed[1].color, .teal)
    }

    func testCreateRejectsBadAndDuplicateNames() throws {
        XCTAssertThrowsError(try store.createProfile(named: "   ")) {
            XCTAssertEqual($0 as? ProfileStoreError, .invalidName)
        }
        try store.createProfile(named: "Work")
        XCTAssertThrowsError(try store.createProfile(named: "work")) { error in
            // Case-insensitive file system: "Claude-work" collides with "Claude-Work".
            if case .alreadyExists = error as? ProfileStoreError {} else {
                XCTFail("unexpected error \(error)")
            }
        }
    }

    func testFoldersMadeByHandShowUpWithDerivedNameAndStableColor() throws {
        let folder = store.supportDirectory.appendingPathComponent("Claude-Side-Project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        // Things that are not profiles.
        try FileManager.default.createDirectory(
            at: store.supportDirectory.appendingPathComponent("Claude"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: store.supportDirectory.appendingPathComponent("Claude Profiles"), withIntermediateDirectories: false)
        try Data().write(to: store.supportDirectory.appendingPathComponent("Claude-not-a-folder"))

        let profiles = store.profiles()
        XCTAssertEqual(profiles.map(\.id), [Profile.defaultID, "Claude-Side-Project"])
        XCTAssertEqual(profiles[1].name, "Side Project")
        XCTAssertEqual(profiles[1].color, ProfileColor.automatic(for: "Claude-Side-Project"))
        XCTAssertEqual(store.profiles()[1].color, profiles[1].color, "color must not change between reads")
    }

    func testSortsCustomProfilesByName() throws {
        try store.createProfile(named: "zeta")
        try store.createProfile(named: "Alpha")
        try store.createProfile(named: "mid")
        XCTAssertEqual(store.profiles().map(\.name), ["Default", "Alpha", "mid", "zeta"])
    }

    func testRenameAndRecolorKeepFolderInPlace() throws {
        let created = try store.createProfile(named: "Work")
        try store.rename(created, to: "Day job")
        try store.setColor(.pink, for: created)

        let updated = store.profiles()[1]
        XCTAssertEqual(updated.id, "Claude-Work")
        XCTAssertEqual(updated.name, "Day job")
        XCTAssertEqual(updated.color, .pink)
        XCTAssertEqual(updated.dataDirectory, created.dataDirectory)

        XCTAssertThrowsError(try store.rename(created, to: "")) {
            XCTAssertEqual($0 as? ProfileStoreError, .invalidName)
        }
    }

    func testDefaultProfileCanBeRelabelledButNotTrashed() throws {
        let stock = store.profiles()[0]
        try store.rename(stock, to: "Personal")
        try store.setColor(.orange, for: stock)
        XCTAssertEqual(store.profiles()[0].name, "Personal")
        XCTAssertEqual(store.profiles()[0].color, .orange)
        XCTAssertThrowsError(try store.trash(stock)) {
            XCTAssertEqual($0 as? ProfileStoreError, .notCustomizable)
        }
    }

    func testLookupByDataDirectory() throws {
        let created = try store.createProfile(named: "Work")
        XCTAssertEqual(store.profile(forDataDirectory: created.dataDirectory)?.id, "Claude-Work")
        XCTAssertEqual(store.profile(forDataDirectory: nil)?.id, Profile.defaultID)
        XCTAssertNil(store.profile(forDataDirectory: URL(fileURLWithPath: "/nowhere")))
    }

    func testMetadataFileIsReadableJSON() throws {
        try store.createProfile(named: "Work", color: .green)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.metadataURL)) as? [String: Any]
        let entry = json?["Claude-Work"] as? [String: Any]
        XCTAssertEqual(entry?["name"] as? String, "Work")
        XCTAssertEqual(entry?["color"] as? String, "green")
    }
}
