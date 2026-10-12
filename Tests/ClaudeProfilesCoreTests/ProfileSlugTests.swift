import XCTest
@testable import ClaudeProfilesCore

final class ProfileSlugTests: XCTestCase {
    func testKeepsSimpleNames() {
        XCTAssertEqual(ProfileSlug.make(from: "Work"), "Work")
        XCTAssertEqual(ProfileSlug.make(from: "client_2"), "client_2")
    }

    func testReplacesRunsOfUnsafeCharactersWithOneDash() {
        XCTAssertEqual(ProfileSlug.make(from: "Work (ACME)"), "Work-ACME")
        XCTAssertEqual(ProfileSlug.make(from: "  side   project  "), "side-project")
        XCTAssertEqual(ProfileSlug.make(from: "a/b\\c:d"), "a-b-c-d")
    }

    func testTrimsLeadingAndTrailingSeparators() {
        XCTAssertEqual(ProfileSlug.make(from: "--hello--"), "hello")
        XCTAssertEqual(ProfileSlug.make(from: ".hidden"), "hidden")
    }

    func testRejectsNamesWithNothingUsable() {
        XCTAssertNil(ProfileSlug.make(from: ""))
        XCTAssertNil(ProfileSlug.make(from: "   "))
        XCTAssertNil(ProfileSlug.make(from: "!!!"))
    }

    func testDisplayNameRestoresSpaces() {
        XCTAssertEqual(ProfileSlug.displayName(fromFolderSuffix: "Side-Project"), "Side Project")
    }
}
