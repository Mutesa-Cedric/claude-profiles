import XCTest
@testable import ClaudeProfilesCore

final class ProcessScannerTests: XCTestCase {
    private let exe = "/Applications/Claude.app/Contents/MacOS/Claude"

    func testFindsStockInstanceWithoutDataDir() {
        let output = "  625 \(exe)\n"
        let found = ProcessScanner.parse(psOutput: output, executablePath: exe)
        XCTAssertEqual(found, [ClaudeProcess(pid: 625, dataDirectory: nil)])
    }

    func testFindsProfileInstanceWithSpacesInPath() {
        let dir = "/Users/me/Library/Application Support/Claude-Work"
        let output = "19302 \(exe) --user-data-dir=\(dir)\n"
        let found = ProcessScanner.parse(psOutput: output, executablePath: exe)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].pid, 19302)
        XCTAssertEqual(found[0].dataDirectory?.path, dir)
    }

    func testStopsDataDirAtNextSwitch() {
        let dir = "/Users/me/Library/Application Support/Claude-Work"
        let output = "7 \(exe) --user-data-dir=\(dir) --no-sandbox\n"
        let found = ProcessScanner.parse(psOutput: output, executablePath: exe)
        XCTAssertEqual(found.first?.dataDirectory?.path, dir)
    }

    func testIgnoresHelpersAndOtherApps() {
        let output = """
          1 /Applications/Claude.app/Contents/Frameworks/Claude Helper (GPU).app/Contents/MacOS/Claude Helper (GPU) --type=gpu-process
          2 /Applications/Claude.app/Contents/MacOS/Claude Helper --type=renderer
          3 /Applications/ClaudeOther.app/Contents/MacOS/Claude
          4 /usr/bin/grep Claude
        garbage line without pid
        """
        XCTAssertEqual(ProcessScanner.parse(psOutput: output, executablePath: exe), [])
    }

    func testKeepsOnlyTheMainProcessPerDataDir() {
        let dir = "/Users/me/Library/Application Support/Claude-Work"
        let output = """
        900 \(exe) --user-data-dir=\(dir) --type=utility --utility-sub-type=network
        880 \(exe) --user-data-dir=\(dir)
        890 \(exe) --user-data-dir=\(dir)
        """
        let found = ProcessScanner.parse(psOutput: output, executablePath: exe)
        XCTAssertEqual(found.map(\.pid), [880])
    }

    func testParsesSeveralInstancesAtOnce() {
        let output = """
        625 \(exe)
        700 \(exe) --user-data-dir=/tmp/Claude-A
        701 \(exe) --user-data-dir=/tmp/Claude-B
        """
        let found = ProcessScanner.parse(psOutput: output, executablePath: exe)
        XCTAssertEqual(found.map(\.pid), [625, 700, 701])
        XCTAssertEqual(found.map { $0.dataDirectory?.lastPathComponent }, [nil, "Claude-A", "Claude-B"])
    }
}
