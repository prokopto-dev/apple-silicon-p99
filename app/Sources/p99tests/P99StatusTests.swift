import P99Core

/// A fully-installed Apple Silicon machine, as scripts/status.sh reports it.
private func tsv(_ overrides: [String: String] = [:]) -> String {
    var base: [String: String] = [
        "clt": "ok", "rosetta": "ok", "brew": "ok", "tools": "ok",
        "wrapper": "ok", "engine": "ok", "prefix": "ok", "fonts": "ok",
        "game": "ok", "p99files": "V62",
        "fix_dsetup": "ok", "fix_dpvs": "ok", "fix_ini": "ok",
    ]
    base.merge(overrides) { _, new in new }
    return base.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n")
}

func runP99StatusTests() {
    let full = P99Status(tsv: tsv())
    T.expect(full.fullyInstalled, "full install is fullyInstalled")
    T.expect(full.anythingInstalled, "full install is anythingInstalled")
    T.expect(full.gameInstalled && full.brewInstalled, "game+brew flags")
    T.equal(full.value("p99files"), "V62", "p99files version readable")

    let empty = P99Status()
    T.expect(!empty.fullyInstalled && !empty.anythingInstalled, "empty status is nothing")
    T.equal(empty.value("clt"), "?", "missing key reads '?'")
    T.expect(!empty.isOK("clt"), "missing key not ok")

    let noGame = P99Status(tsv: tsv(["game": "missing", "p99files": "n/a",
                                     "fix_dsetup": "n/a", "fix_dpvs": "n/a", "fix_ini": "n/a"]))
    T.expect(!noGame.fullyInstalled, "missing game blocks fullyInstalled")
    T.expect(noGame.anythingInstalled, "wrapper alone counts as anythingInstalled")
    T.expect(!noGame.gameInstalled, "gameInstalled false")

    // Intel Mac: rosetta n/a must not block a complete install.
    let intel = P99Status(tsv: tsv(["rosetta": "n/a"]))
    T.expect(intel.isDone("rosetta") && !intel.isOK("rosetta"), "n/a is done but not ok")
    T.expect(intel.fullyInstalled, "Intel n/a rosetta still fullyInstalled")

    T.expect(P99Status(tsv: "p99files\tV62").isOK("p99files"), "Vnn is ok")
    T.expect(!P99Status(tsv: "p99files\tnone").isOK("p99files"), "none is not ok")
    T.expect(!P99Status(tsv: "p99files\tn/a").isOK("p99files"), "n/a is not ok")
    T.expect(P99Status(tsv: "p99files\tn/a").isDone("p99files"), "n/a is done")

    T.expect(!P99Status(tsv: tsv(["fix_dpvs": "missing"])).fullyInstalled,
             "one missing fix blocks fullyInstalled")

    // Waiving (the app's "V58 fix disabled" setting).
    let noDsetup = P99Status(tsv: tsv(["fix_dsetup": "missing"]))
    T.expect(!noDsetup.fullyInstalled, "missing dsetup blocks by default")
    T.expect(noDsetup.fullyInstalled(waiving: ["fix_dsetup"]), "waived dsetup satisfies")
    T.expect(!noDsetup.fullyInstalled(waiving: ["fix_dpvs"]), "waiving the wrong key doesn't help")
    let noGame2 = P99Status(tsv: tsv(["game": "missing"]))
    T.expect(!noGame2.fullyInstalled(waiving: ["game"]), "the game itself can never be waived")

    let malformed = P99Status(tsv: "garbage line no tab\n\nclt\tok")
    T.expect(malformed.isOK("clt"), "valid line survives malformed neighbors")
    T.equal(malformed.value("garbage line no tab"), "?", "malformed line ignored")

    // Informational performance keys must never gate readiness — they are not in
    // requiredKeys, so any value (including "missing") leaves fullyInstalled intact.
    let withPerf = P99Status(tsv: tsv(["renderer": "d9vk", "moltenvk": "cx", "perf_ini": "ok"]))
    T.expect(withPerf.fullyInstalled, "renderer/moltenvk/perf_ini don't affect fullyInstalled")
    T.equal(withPerf.value("renderer"), "d9vk", "renderer value readable")
    T.equal(withPerf.value("moltenvk"), "cx", "moltenvk value readable")
    let offPerf = P99Status(tsv: tsv(["renderer": "wined3d", "perf_ini": "missing"]))
    T.expect(offPerf.fullyInstalled, "perf_ini missing doesn't block readiness")
}
