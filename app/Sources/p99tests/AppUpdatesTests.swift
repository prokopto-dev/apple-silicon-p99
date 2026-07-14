import Foundation
import P99Core

private let fixtureJSON = """
[
  {"tag_name": "v0.2.0", "name": "v0.2.0", "body": "### Added\\n- toggle",
   "html_url": "https://example.com/v0.2.0", "draft": false, "prerelease": false},
  {"tag_name": "engine-mirror-1", "name": "Mirrored components", "body": "mirror",
   "html_url": "https://example.com/mirror", "draft": false, "prerelease": false},
  {"tag_name": "v0.3.0", "name": null, "body": "### Added\\n- updates window",
   "html_url": "https://example.com/v0.3.0", "draft": false, "prerelease": false},
  {"tag_name": "v0.4.0", "name": "draft", "body": "wip",
   "html_url": "https://example.com/v0.4.0", "draft": true, "prerelease": false},
  {"tag_name": "v0.10.0-beta", "name": "beta", "body": "beta",
   "html_url": "https://example.com/beta", "draft": false, "prerelease": true},
  {"tag_name": "v0.1.1", "name": "v0.1.1", "body": "first",
   "html_url": "https://example.com/v0.1.1", "draft": false, "prerelease": false}
]
""".data(using: .utf8)!

func runAppUpdatesTests() {
    // Version parsing.
    T.equal(AppUpdates.parseVersion("v0.2.0") ?? [], [0, 2, 0], "parses v-prefixed semver")
    T.equal(AppUpdates.parseVersion("1.10") ?? [], [1, 10], "parses two-part version")
    T.equal(AppUpdates.parseVersion("v0.3.0-beta") ?? [], [0, 3, 0], "strips prerelease suffix")
    T.expect(AppUpdates.parseVersion("engine-mirror-1") == nil, "utility tag isn't a version")
    T.expect(AppUpdates.parseVersion("") == nil, "empty string isn't a version")

    // Comparison: numeric, not lexicographic; right-padded.
    T.expect(AppUpdates.isNewer([0, 10, 0], than: [0, 9, 9]), "0.10.0 beats 0.9.9")
    T.expect(!AppUpdates.isNewer([0, 2, 0], than: [0, 2]), "0.2.0 == 0.2 (padding)")
    T.expect(!AppUpdates.isNewer([0, 2, 0], than: [0, 2, 0]), "equal isn't newer")
    T.expect(AppUpdates.isNewer([1], than: [0, 99, 99]), "major bump wins")

    // GitHub JSON parsing: drops drafts, prereleases, and non-semver tags.
    do {
        let releases = try AppUpdates.releases(fromJSON: fixtureJSON)
        T.equal(releases.map(\.tag).sorted(), ["v0.1.1", "v0.2.0", "v0.3.0"],
                "keeps only published semver releases")
        T.equal(releases.first { $0.tag == "v0.3.0" }?.title ?? "", "v0.3.0",
                "null name falls back to tag")

        // Missed-release selection, newest first.
        let missed = AppUpdates.newer(than: "0.1.1", in: releases)
        T.equal(missed.map(\.tag), ["v0.3.0", "v0.2.0"], "newer-than filters and sorts")
        T.expect(AppUpdates.newer(than: "0.3.0", in: releases).isEmpty, "up to date -> empty")
        T.equal(AppUpdates.newer(than: "0.0.0", in: releases).count, 3, "fresh dev build sees all")
    } catch {
        T.expect(false, "fixture JSON must parse: \(error)")
    }
}
