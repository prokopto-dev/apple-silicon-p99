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
    let withPerf = P99Status(tsv: tsv(["renderer": "d9vk", "moltenvk": "cx",
                                       "dxvk_maps": "indirect", "perf_ini": "ok"]))
    T.expect(withPerf.fullyInstalled, "renderer/moltenvk/dxvk_maps/perf_ini don't affect fullyInstalled")
    T.equal(withPerf.value("renderer"), "d9vk", "renderer value readable")
    T.equal(withPerf.value("moltenvk"), "cx", "moltenvk value readable")
    T.equal(withPerf.value("dxvk_maps"), "indirect", "dxvk_maps value readable")
    let offPerf = P99Status(tsv: tsv(["renderer": "wined3d", "perf_ini": "missing"]))
    T.expect(offPerf.fullyInstalled, "perf_ini missing doesn't block readiness")

    // The wrapper-knob and wined3d-tuning keys (55-wrapper.sh / 65-wined3d.sh)
    // are informational exactly like the ones above — any value, including the
    // Linux CI's n/a degradations, must leave readiness untouched.
    let withKnobs = P99Status(tsv: tsv(["winedebug": "quiet", "hidpi": "off",
                                        "metal_hud": "on", "wined3d_csmt": "off",
                                        "wined3d_maxgl": "2.1", "wined3d_vram": "512",
                                        "wined3d_renderer": "gl"]))
    T.expect(withKnobs.fullyInstalled, "wrapper/wined3d knob keys don't affect fullyInstalled")
    T.equal(withKnobs.value("hidpi"), "off", "hidpi value readable")
    T.equal(withKnobs.value("metal_hud"), "on", "metal_hud value readable")
    T.equal(withKnobs.value("winedebug"), "quiet", "winedebug value readable")
    T.equal(withKnobs.value("wined3d_csmt"), "off", "wined3d_csmt value readable")
    T.equal(withKnobs.value("wined3d_maxgl"), "2.1", "wined3d_maxgl value readable")
    let naKnobs = P99Status(tsv: tsv(["winedebug": "n/a", "hidpi": "n/a",
                                      "metal_hud": "n/a", "wined3d_csmt": "n/a"]))
    T.expect(naKnobs.fullyInstalled, "n/a knob degradations don't affect fullyInstalled")

    // Experimental FEX stack keys are informational too — no state of the FEX
    // side may ever gate the supported install's readiness.
    let fexMissing = P99Status(tsv: tsv(["stack": "rosetta", "fex_pinned": "missing",
                                         "fex_wrapper": "missing", "fex_engine": "missing",
                                         "fex_prefix": "missing", "fex_smoke": "n/a"]))
    T.expect(fexMissing.fullyInstalled, "absent FEX stack doesn't affect fullyInstalled")
    T.expect(!fexMissing.fexEnginePinned && !fexMissing.fexInstalled, "fex gates read missing")
    let fexLive = P99Status(tsv: tsv(["stack": "fex", "fex_pinned": "ok",
                                      "fex_wrapper": "ok", "fex_engine": "ok",
                                      "fex_prefix": "ok", "fex_smoke": "fail"]))
    T.expect(fexLive.fullyInstalled, "even a failing FEX stack doesn't affect fullyInstalled")
    T.expect(fexLive.fexEnginePinned && fexLive.fexInstalled, "fex gates read ok")
    T.equal(fexLive.activeStack, "fex", "activeStack readable")
    T.equal(fexLive.fexSmoke, "fail", "fexSmoke readable")

    // Old status.sh output (pre-stack) must read as the supported stack.
    T.equal(full.activeStack, "rosetta", "no stack key defaults to rosetta")
    T.equal(full.fexSmoke, "n/a", "no smoke key defaults to n/a")
}
