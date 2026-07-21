import P99Core
import SwiftUI

/// Shared screen for every script pipeline: install, update, uninstall, launch.
/// Shows the step list, the current `==>` status line, a progress bar during
/// downloads, and a collapsible raw log.
@MainActor
struct RunView: View {
    @Environment(InstallerModel.self) private var model
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(model.runKind.title)
                    .font(.title2.bold())
                if model.runKind == .launch, model.runState == .running {
                    Text("On every launch the anti-cheat unpacks for 1–2 minutes with no window "
                         + "and 100% CPU. That's normal — don't force-quit it.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .padding(.vertical, 16)
            Divider()

            HStack(alignment: .top, spacing: 0) {
                if model.steps.count > 1 {
                    stepList
                        .frame(width: 220)
                        .padding(12)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 14) {
                    stateHeader
                    if model.runState == .running {
                        if let pct = model.percent {
                            SwiftUI.ProgressView(value: pct, total: 100)
                            Text("\(Int(pct))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            SwiftUI.ProgressView()
                                .progressViewStyle(.linear)
                        }
                    }
                    DisclosureGroup("Details", isExpanded: $showLog) {
                        logView
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
        }
        .onChange(of: model.runState) { _, new in
            if case .failure = new { showLog = true }
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 8) {
                    stepIcon(index)
                    Text(step.title)
                        .font(.callout)
                        .foregroundStyle(index <= model.currentStep ? .primary : .secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func stepIcon(_ index: Int) -> some View {
        if index < model.currentStep {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if index == model.currentStep {
            switch model.runState {
            case .running:
                SwiftUI.ProgressView().controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failure:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        } else {
            Image(systemName: "circle").foregroundStyle(.quaternary)
        }
    }

    @ViewBuilder
    private var stateHeader: some View {
        switch model.runState {
        case .running:
            Text(model.headline.isEmpty ? "Starting…" : model.headline)
                .font(.headline)
        case .success:
            Label(successMessage, systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Something went wrong", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .textSelection(.enabled)
                Text("It's safe to try again — setup resumes where it left off. "
                     + "If it keeps failing, the log below is what to share in the "
                     + "P99 forums' Mac thread.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var successMessage: String {
        switch model.runKind {
        case .install:     "Install complete — ready to play!"
        case .update:      "Up to date."
        case .uninstall:   "Uninstall finished."
        case .launch:      "The game engine is up — have fun!"
        case .performance: "Performance settings applied."
        }
    }

    private var logView: some View {
        ScrollView {
            Text(model.logLines.suffix(600).joined(separator: "\n"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
        .frame(height: 180)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .defaultScrollAnchor(.bottom)
    }

    private var footer: some View {
        HStack {
            Spacer()
            switch model.runState {
            case .running:
                Button("Cancel") { model.cancelRun() }
                    .help("Safe to cancel — nothing breaks; re-running resumes where it left off")
            case .success:
                Button("Done") { model.backToStatus() }
                if model.runKind == .install || model.runKind == .update {
                    Button("Play") { model.play() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            case .failure:
                Button("Back") { model.backToStatus() }
                Button("Try Again") { model.backToStatus(); model.beginInstall() }
                    .buttonStyle(.borderedProminent)
                    .opacity(model.runKind == .install ? 1 : 0)
            }
        }
        .padding(14)
    }
}
