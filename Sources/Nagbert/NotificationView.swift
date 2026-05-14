import SwiftUI
import NagbertCore

struct NotificationView: View {
    @ObservedObject var model: NotificationModel
    weak var manager: NotificationManager?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    levelIcon
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.payload.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if let body = model.payload.body, !body.isEmpty {
                            Text(body)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                        if model.phase == .failed, !model.stderrPreview.isEmpty {
                            Text(model.stderrPreview)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                        if model.showFullError {
                            ScrollView {
                                Text(model.stderrString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(6)
                            }
                            .frame(maxHeight: 160)
                            .background(Color.black.opacity(0.06))
                            .cornerRadius(6)
                        }
                    }
                    Spacer(minLength: 0)
                }
                actionRow
            }
            .padding(12)

            if hovering {
                Button(action: { manager?.dismiss(model) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .frame(width: 340)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .onHover { hovering = $0 }
        .shake(active: model.shaking)
    }

    @ViewBuilder
    private var levelIcon: some View {
        switch model.payload.level {
        case .info:
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
        case .warn:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .urgent:
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        let hasPerform = (model.payload.performAction?.isEmpty == false)
        let hasDoc = (model.payload.documentation?.isEmpty == false)
        HStack(spacing: 8) {
            if hasPerform {
                Button(action: { manager?.performAction(for: model) }) {
                    HStack(spacing: 4) {
                        if model.phase == .performing || model.phase == .checking {
                            ProgressView().controlSize(.small)
                        }
                        Text(performButtonLabel)
                    }
                }
                .controlSize(.small)
                .disabled(model.phase == .performing || model.phase == .checking || model.phase == .resolved)
            }
            if model.phase == .failed, !model.errorBuffer.isEmpty {
                Button(model.showFullError ? "Hide error" : "Show full error") {
                    model.showFullError.toggle()
                }
                .controlSize(.small)
            }
            if hasDoc {
                Button("Docs") { manager?.openDocumentation(for: model) }
                    .controlSize(.small)
            }
            Spacer()
            Button("Dismiss") { manager?.dismiss(model) }
                .controlSize(.small)
        }
        .font(.system(size: 11))
    }

    private var performButtonLabel: String {
        switch model.phase {
        case .performing: return "Running…"
        case .checking: return "Checking…"
        case .resolved: return "Done"
        case .failed: return "Retry"
        default: return "Perform"
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
