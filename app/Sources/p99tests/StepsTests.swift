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
}
