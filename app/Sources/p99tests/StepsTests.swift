import Foundation
import P99Core

func runStepsTests() {
    let existing = Steps.install(source: .existing)
    T.equal(existing.map(\.script),
            ["00-prereqs.sh", "10-build-wrapper.sh", "20-install-game.sh", "30-apply-mac-fixes.sh"],
            "existing source: prereqs, wrapper, game, fixes")
    T.expect(existing.allSatisfy { $0.arguments.isEmpty }, "existing source: no arguments")

    let folder = Steps.install(source: .folder(URL(fileURLWithPath: "/tmp/Titanium")))
    T.equal(folder.first { $0.script == "20-install-game.sh" }?.arguments ?? [],
            ["/tmp/Titanium"], "folder source: path passed to 20")

    let isos = Steps.install(source: .isos([URL(fileURLWithPath: "/tmp/d1.iso"),
                                            URL(fileURLWithPath: "/tmp/d2.iso")]))
    T.equal(isos.map(\.script),
            ["00-prereqs.sh", "10-build-wrapper.sh", "15-install-from-media.sh",
             "20-install-game.sh", "30-apply-mac-fixes.sh"],
            "iso source: media step inserted before game step")
    T.equal(isos.first { $0.script == "15-install-from-media.sh" }?.arguments ?? [],
            ["/tmp/d1.iso", "/tmp/d2.iso"], "iso source: all isos passed to 15")
    // 20 must run bare so it uses the GAME_DIR that 15 just populated.
    T.expect(isos.first { $0.script == "20-install-game.sh" }?.arguments.isEmpty == true,
             "iso source: 20 runs with no args")

    for source: SourceChoice in [.existing, .folder(URL(fileURLWithPath: "/x")),
                                 .isos([URL(fileURLWithPath: "/y.iso")])] {
        T.equal(Steps.install(source: source).last?.script ?? "", "30-apply-mac-fixes.sh",
                "fixes always last")
    }

    // Performance run: stack recorded first (so the renderer applies inside the
    // wrapper future launches use), then renderer, then the eqclient.ini keys.
    // All take their apply/revert mode from the environment — no positional args.
    let perf = Steps.performance()
    T.equal(perf.map(\.script), ["70-stack.sh", "60-renderer.sh", "35-perf-ini.sh"],
            "performance: stack, renderer, then eqclient.ini")
    T.expect(perf.allSatisfy { $0.arguments.isEmpty }, "performance: no arguments (mode via env)")

    // FEX setup pipeline: build the side-by-side wrapper, link the shared game
    // dir, record the stack, smoke-test — all under the P99_STACK=fex overlay.
    let fex = Steps.fexSetup()
    T.equal(fex.map(\.script),
            ["10-build-wrapper.sh", "20-install-game.sh", "70-stack.sh", "75-fex-smoke.sh"],
            "fexSetup: build, link, switch, smoke")
    // 20 must run bare so it reuses the existing shared GAME_DIR (never copies).
    T.expect(fex.allSatisfy { $0.arguments.isEmpty }, "fexSetup: no arguments (stack via env)")
    T.equal(Steps.fexSetupEnv(), ["P99_STACK": "fex"], "fexSetup: env overlay is exactly P99_STACK")

    // The panel-choice → script-env contract (docs/PERFORMANCE.md documents the
    // same variables). Everything off must still run the INI patcher in revert
    // mode so previously applied keys get cleaned out.
    let off = Steps.performanceEnv(stack: "rosetta", renderer: "wined3d", smoother: false,
                                   indirectMaps: false, fpsCap: "", rendererDebug: false,
                                   fpsOverlay: false)
    T.equal(off["P99_STACK"] ?? "", "rosetta", "perfEnv: stack passthrough")
    T.equal(off["P99_RENDERER"] ?? "", "wined3d", "perfEnv: renderer passthrough")
    T.equal(off["P99_APPLY_PERF"] ?? "", "0", "perfEnv: all-off reverts the INI keys")
    T.equal(off["P99_DXVK_INDIRECT_MAPS"] ?? "?", "", "perfEnv: indirect maps off is empty")

    let allOn = Steps.performanceEnv(stack: "fex", renderer: "d9vk", smoother: true,
                                     indirectMaps: true, fpsCap: "60", rendererDebug: true,
                                     fpsOverlay: true)
    T.equal(allOn["P99_STACK"] ?? "", "fex", "perfEnv: fex stack passthrough")
    T.equal(allOn["P99_APPLY_PERF"] ?? "", "1", "perfEnv: smoother applies INI")
    T.equal(allOn["P99_PERF_PROFILE"] ?? "", "smoother", "perfEnv: smoother profile")
    T.equal(allOn["EQ_FPS_CAP"] ?? "", "60", "perfEnv: fps cap passthrough")
    T.equal(allOn["P99_DXVK_INDIRECT_MAPS"] ?? "", "1", "perfEnv: indirect maps on")
    T.equal(allOn["P99_RENDERER_DEBUG"] ?? "", "1", "perfEnv: debug on")
    T.equal(allOn["P99_DXVK_HUD"] ?? "", "fps,frametimes", "perfEnv: hud value")

    // An FPS cap alone must run the INI patcher in apply mode (no smoother profile).
    let capOnly = Steps.performanceEnv(stack: "rosetta", renderer: "wined3d", smoother: false,
                                       indirectMaps: false, fpsCap: "30", rendererDebug: false,
                                       fpsOverlay: false)
    T.equal(capOnly["P99_APPLY_PERF"] ?? "", "1", "perfEnv: cap alone applies INI")
    T.equal(capOnly["P99_PERF_PROFILE"] ?? "?", "", "perfEnv: cap alone has no profile")
}
