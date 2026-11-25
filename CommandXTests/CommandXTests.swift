// CommandXTests.swift
// CommandXTests
//
// Unit tests for path-parsing logic extracted from AppDelegate.

import XCTest
@testable import CommandX

final class CommandXTests: XCTestCase {

    // MARK: - parseFinderPaths

    func testNormalPaths() {
        let output = "/Users/alice/file.txt\0/Users/alice/document.pdf\0"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0], URL(fileURLWithPath: "/Users/alice/file.txt"))
        XCTAssertEqual(urls[1], URL(fileURLWithPath: "/Users/alice/document.pdf"))
    }

    func testPathsWithSpaces() {
        let output = "/Users/alice/my documents/report Q1.pdf\0/Users/alice/photo library/IMG 001.jpg\0"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].path, "/Users/alice/my documents/report Q1.pdf")
        XCTAssertEqual(urls[1].path, "/Users/alice/photo library/IMG 001.jpg")
    }

    func testPathsWithUnicode() {
        let output = "/Users/alice/日本語/ファイル.txt\0/Users/alice/Ünïcödé foldér/résumé.docx\0"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].path, "/Users/alice/日本語/ファイル.txt")
        XCTAssertEqual(urls[1].path, "/Users/alice/Ünïcödé foldér/résumé.docx")
    }

    func testNulDelimiterWithoutTrailingNul() {
        // Defensive: no trailing \0
        let output = "/Users/alice/a.txt\0/Users/alice/b.txt"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].path, "/Users/alice/a.txt")
        XCTAssertEqual(urls[1].path, "/Users/alice/b.txt")
    }

    func testEmptyString() {
        let urls = parseFinderPaths("")
        XCTAssertTrue(urls.isEmpty)
    }

    func testSinglePath() {
        let output = "/Users/alice/only.txt\0"
        let urls = parseFinderPaths(output)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].path, "/Users/alice/only.txt")
    }

    func testOnlyNulCharacters() {
        let output = "\0\0\0"
        let urls = parseFinderPaths(output)
        XCTAssertTrue(urls.isEmpty)
    }

    // MARK: - Updater

    func testVersionComparison() {
        XCTAssertTrue(isNewerVersion("v1.1.3", than: "1.1.2"))
        XCTAssertTrue(isNewerVersion("1.2", than: "1.1.9"))
        XCTAssertTrue(isNewerVersion("v2.0.0", than: "1.9.9"))
        XCTAssertFalse(isNewerVersion("v1.1.2", than: "1.1.2"))
        XCTAssertFalse(isNewerVersion("1.1", than: "1.1.0"))
        XCTAssertFalse(isNewerVersion("v1.0.9", than: "1.1.0"))
    }

    func testParseLatestReleasePicksTrustedAssets() throws {
        let base = "https://github.com/ToRa89/command-x/releases/download/v1.2.0"
        let json = """
        {"tag_name":"v1.2.0","html_url":"https://github.com/ToRa89/command-x/releases/tag/v1.2.0",
         "assets":[
          {"name":"CommandX-1.2.0.dmg","browser_download_url":"\(base)/CommandX-1.2.0.dmg"},
          {"name":"SHA256SUMS.txt","browser_download_url":"\(base)/SHA256SUMS.txt"}]}
        """
        let info = try parseLatestRelease(Data(json.utf8))
        XCTAssertEqual(info.version, "v1.2.0")
        XCTAssertEqual(info.dmgURL?.lastPathComponent, "CommandX-1.2.0.dmg")
        XCTAssertNotNil(info.sumsURL)
    }

    func testParseLatestReleaseRejectsForeignHost() throws {
        let json = """
        {"tag_name":"v9.9.9","html_url":"https://github.com/ToRa89/command-x/releases/tag/v9.9.9",
         "assets":[{"name":"evil.dmg","browser_download_url":"https://evil.example.com/ToRa89/command-x/releases/download/v9/evil.dmg"}]}
        """
        let info = try parseLatestRelease(Data(json.utf8))
        XCTAssertNil(info.dmgURL)
    }

    func testExpectedHashLookup() {
        let sums = "ABC123  CommandX-1.2.0.dmg\ndef456  CommandX-1.2.0.dmg.zip\n"
        XCTAssertEqual(expectedHash(for: "CommandX-1.2.0.dmg", in: sums), "abc123")
        XCTAssertEqual(expectedHash(for: "CommandX-1.2.0.dmg.zip", in: sums), "def456")
        XCTAssertNil(expectedHash(for: "other.dmg", in: sums))
    }
}
