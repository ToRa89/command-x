// UpdateChecker.swift
// Command X
//
// Checks GitHub Releases for a newer version and can install it in place:
// download DMG -> verify SHA-256 against SHA256SUMS.txt -> copy app out of the DMG
// -> verify signature -> swap the app after quit -> relaunch.

import AppKit
import Combine
import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "enablestartup.CommandX", category: "update")

// MARK: - Pure helpers (unit tested)

nonisolated enum UpdateConfig {
    static let repo = "ToRa89/command-x"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    /// Downloads are only accepted from this release path.
    static let allowedDownloadPrefix = "/\(repo)/releases/download/"
}

nonisolated struct ReleaseInfo: Equatable {
    let version: String
    let pageURL: URL
    let dmgURL: URL?
    let sumsURL: URL?
}

nonisolated enum UpdateError: LocalizedError {
    case badResponse
    case noDMG
    case hashMissing
    case hashMismatch
    case commandFailed(String)
    case notWritable

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from GitHub."
        case .noDMG: return "The release has no DMG attached."
        case .hashMissing: return "No checksum found for the DMG."
        case .hashMismatch: return "Checksum of the download does not match. Update aborted."
        case .commandFailed(let what): return "Update step failed: \(what)"
        case .notWritable: return "Command X cannot replace itself at this location."
        }
    }
}

/// "v1.2.3" -> [1, 2, 3]; missing parts count as 0.
nonisolated func parseVersion(_ string: String) -> [Int] {
    let trimmed = string.hasPrefix("v") || string.hasPrefix("V") ? String(string.dropFirst()) : string
    return trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
}

nonisolated func isNewerVersion(_ remote: String, than local: String) -> Bool {
    let r = parseVersion(remote), l = parseVersion(local)
    for i in 0..<max(r.count, l.count) {
        let a = i < r.count ? r[i] : 0
        let b = i < l.count ? l[i] : 0
        if a != b { return a > b }
    }
    return false
}

private nonisolated func isTrustedDownload(_ url: URL) -> Bool {
    url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix(UpdateConfig.allowedDownloadPrefix)
}

nonisolated func parseLatestRelease(_ data: Data) throws -> ReleaseInfo {
    struct Asset: Decodable { let name: String; let browser_download_url: URL }
    struct Release: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset] }
    let release: Release
    do { release = try JSONDecoder().decode(Release.self, from: data) } catch { throw UpdateError.badResponse }
    let dmg = release.assets.first { $0.name.hasSuffix(".dmg") && isTrustedDownload($0.browser_download_url) }
    let sums = release.assets.first { $0.name == "SHA256SUMS.txt" && isTrustedDownload($0.browser_download_url) }
    return ReleaseInfo(version: release.tag_name, pageURL: release.html_url,
                       dmgURL: dmg?.browser_download_url, sumsURL: sums?.browser_download_url)
}

/// Finds the hash for `fileName` in `shasum -a 256` output ("<hash>  <name>" per line).
nonisolated func expectedHash(for fileName: String, in sums: String) -> String? {
    for line in sums.split(whereSeparator: \.isNewline) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == fileName {
            return String(parts[0]).lowercased()
        }
    }
    return nil
}

// MARK: - Checker

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Asks GitHub for the latest release. Returns the release if it is newer than this app.
    @discardableResult
    func check() async -> ReleaseInfo? {
        if case .installing = state { return nil }
        state = .checking
        do {
            var request = URLRequest(url: UpdateConfig.latestReleaseURL, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("CommandX-Updater", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
            let release = try parseLatestRelease(data)
            if isNewerVersion(release.version, than: Self.currentVersion) {
                state = .available(release)
                return release
            }
            state = .upToDate
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
        return nil
    }

    /// Downloads, verifies and installs the given release, then relaunches.
    func install(_ release: ReleaseInfo) async {
        guard let dmgURL = release.dmgURL, let sumsURL = release.sumsURL else {
            state = .failed(UpdateError.noDMG.localizedDescription)
            return
        }
        let dest = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            state = .failed(UpdateError.notWritable.localizedDescription)
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        state = .installing
        do {
            let staged = try await Task.detached(priority: .userInitiated) {
                try await Self.stage(dmgURL: dmgURL, sumsURL: sumsURL)
            }.value
            try Self.relaunchWithSwap(newApp: staged.app, workDir: staged.workDir, destination: dest)
            NSApp.terminate(nil)
        } catch {
            logger.error("Update install failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Steps

    private nonisolated static func stage(dmgURL: URL, sumsURL: URL) async throws -> (app: URL, workDir: URL) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("CommandXUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            // 1. download DMG + checksums
            let (tmpDMG, _) = try await URLSession.shared.download(from: dmgURL)
            let dmg = work.appendingPathComponent(dmgURL.lastPathComponent)
            try fm.moveItem(at: tmpDMG, to: dmg)
            let (sumsData, _) = try await URLSession.shared.data(from: sumsURL)

            // 2. verify SHA-256
            guard let expected = expectedHash(for: dmg.lastPathComponent, in: String(decoding: sumsData, as: UTF8.self)) else {
                throw UpdateError.hashMissing
            }
            let actual = SHA256.hash(data: try Data(contentsOf: dmg, options: .mappedIfSafe))
                .map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw UpdateError.hashMismatch }

            // 3. mount, copy the app out, unmount
            let mount = work.appendingPathComponent("mnt")
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path, dmg.path])
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
            let newApp = work.appendingPathComponent("CommandX.app")
            try run("/usr/bin/ditto", [mount.appendingPathComponent("CommandX.app").path, newApp.path])

            // 4. the copy must have a valid signature
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            return (newApp, work)
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }
    }

    /// Starts a detached helper that waits for this process to exit, swaps the app and reopens it.
    private nonisolated static func relaunchWithSwap(newApp: URL, workDir: URL, destination: URL) throws {
        let script = workDir.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/bash
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$3.old"
        if mv "$3" "$3.old" && /usr/bin/ditto "$2" "$3"; then
            rm -rf "$3.old"
        else
            rm -rf "$3"; mv "$3.old" "$3"
        fi
        /usr/bin/open "$3"
        rm -rf "$4"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                       newApp.path, destination.path, workDir.path]
        try p.run()
    }

    @discardableResult
    private nonisolated static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else {
            throw UpdateError.commandFailed("\((path as NSString).lastPathComponent): \(out.prefix(200))")
        }
        return out
    }
}
