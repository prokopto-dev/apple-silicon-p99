import Foundation

/// One published installer release, as shown in the update window.
/// `notes` is the GitHub Release body — which, thanks to the release
/// pipeline, is exactly that version's CHANGELOG.md section.
public struct AppRelease: Equatable, Identifiable, Sendable {
    public let tag: String        // "v0.2.0"
    public let version: [Int]     // [0, 2, 0]
    public let title: String
    public let notes: String
    public let url: URL           // release page (where the zip lives)
    public let downloadURL: URL?  // the P99-Installer.zip asset, when published

    public var id: String { tag }
    public var versionString: String { version.map(String.init).joined(separator: ".") }

    public init(tag: String, version: [Int], title: String, notes: String, url: URL,
                downloadURL: URL? = nil) {
        self.tag = tag
        self.version = version
        self.title = title
        self.notes = notes
        self.url = url
        self.downloadURL = downloadURL
    }
}

public enum AppUpdates {
    public static let releasesAPI =
        URL(string: "https://api.github.com/repos/prokopto-dev/apple-silicon-p99/releases?per_page=30")!

    /// "v0.2.0" / "0.2.0" -> [0,2,0]; nil for anything non-semver
    /// (e.g. the "engine-mirror-1" asset-hosting tag).
    public static func parseVersion(_ s: String) -> [Int]? {
        var body = s.hasPrefix("v") ? String(s.dropFirst()) : s
        if let dash = body.firstIndex(of: "-") { body = String(body[..<dash]) } // strip -beta etc.
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var nums: [Int] = []
        for p in parts {
            guard let n = Int(p), n >= 0 else { return nil }
            nums.append(n)
        }
        return nums
    }

    /// Numeric, right-padded comparison: [0,10,0] beats [0,9,9]; [0,2] == [0,2,0].
    public static func isNewer(_ a: [Int], than b: [Int]) -> Bool {
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Release-asset filename the pipeline publishes (release.yml `make zip`).
    public static let zipAssetName = "P99-Installer.zip"

    private struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [GitHubAsset]?
    }

    /// Parses the GitHub releases API response, keeping only published
    /// semver-tagged releases (drops drafts, prereleases, and utility tags
    /// like engine-mirror-1).
    public static func releases(fromJSON data: Data) throws -> [AppRelease] {
        try JSONDecoder().decode([GitHubRelease].self, from: data).compactMap { r in
            guard !r.draft, !r.prerelease, let v = parseVersion(r.tag_name) else { return nil }
            return AppRelease(tag: r.tag_name,
                              version: v,
                              title: r.name?.isEmpty == false ? r.name! : r.tag_name,
                              notes: r.body ?? "",
                              url: r.html_url,
                              downloadURL: r.assets?
                                  .first { $0.name == zipAssetName }?
                                  .browser_download_url)
        }
    }

    /// Whether an update can be installed in place ("incrementally") rather
    /// than routed to the release page: only within the same major version.
    /// A major bump may change installation layout or requirements, so it
    /// stays a deliberate, manual download.
    public static func canAutoUpdate(from current: String, to target: [Int]) -> Bool {
        guard let cur = parseVersion(current) else { return false }
        return (cur.first ?? 0) == (target.first ?? 0) && isNewer(target, than: cur)
    }

    /// Releases strictly newer than `current` (a version string like "0.1.1"),
    /// newest first — i.e. everything the user is missing.
    public static func newer(than current: String, in all: [AppRelease]) -> [AppRelease] {
        let cur = parseVersion(current) ?? [0]
        return all.filter { isNewer($0.version, than: cur) }
                  .sorted { isNewer($0.version, than: $1.version) }
    }
}
