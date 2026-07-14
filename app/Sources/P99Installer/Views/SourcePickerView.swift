import SwiftUI
import UniformTypeIdentifiers

/// EverQuest Titanium is proprietary, so the user must supply it: either an
/// existing install folder (copied from an old PC etc.) or the original
/// discs/ISOs, which run through the real Windows installer under Wine.
struct SourcePickerView: View {
    @Environment(InstallerModel.self) private var model
    @State private var isoURLs: [URL] = []
    @State private var folderError: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Where are your EverQuest Titanium files?")
                    .font(.title2.bold())
                Text("Titanium is Sony's 2005 retail release; it can't be downloaded here. "
                     + "Point the installer at a copy you own.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.vertical, 18)
            Divider()

            VStack(spacing: 16) {
                optionCard(
                    icon: "folder",
                    title: "I have a Titanium install folder",
                    detail: "A folder containing eqgame.exe — copied from an old PC, "
                          + "a backup drive, or an existing install. It will be copied "
                          + "to ~/Games/EverQuest (~4.5 GB).",
                    button: "Choose Folder…",
                    action: pickFolder
                )
                if let folderError {
                    Text(folderError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                optionCard(
                    icon: "opticaldisc",
                    title: "I have the original discs or ISO files",
                    detail: "Select all disc images at once (Disc 1 must be included). "
                          + "For physical discs, insert them and select the disc volumes. "
                          + "The original Windows installer will open in a window — click "
                          + "through it with the default location, and at the end UNCHECK "
                          + "any “launch EverQuest / run LaunchPad” box.",
                    button: isoURLs.isEmpty ? "Choose Discs / ISO Files…" : "\(isoURLs.count) selected — change…",
                    action: pickISOs
                )
                if !isoURLs.isEmpty {
                    Button("Start Install from \(isoURLs.count) disc\(isoURLs.count == 1 ? "" : "s")") {
                        model.install(source: .isos(isoURLs))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            Spacer()
            Divider()
            HStack {
                Button("Back") { model.backToStatus() }
                Spacer()
                Text(".bin/.cue rips aren't supported directly — convert them to ISO first (brew install bchunk).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
    }

    private func optionCard(icon: String, title: String, detail: String,
                            button: String, action: @escaping () -> Void) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(button, action: action)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Select your EverQuest Titanium folder (it contains eqgame.exe)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("eqgame.exe").path) else {
            folderError = "“\(url.lastPathComponent)” doesn't look like an EverQuest install — no eqgame.exe inside."
            return
        }
        folderError = nil
        model.install(source: .folder(url))
    }

    private func pickISOs() {
        let panel = NSOpenPanel()
        // Directories allowed too: a mounted physical disc (/Volumes/EQ_DISC1)
        // is a valid source for 15-install-from-media.sh.
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Select ALL your Titanium disc images or mounted discs (hold ⌘ to multi-select)"
        var types: [UTType] = [.diskImage]
        if let iso = UTType(filenameExtension: "iso") { types.append(iso) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        isoURLs = panel.urls
    }
}
