import RouteBarKit
import SwiftUI

/// The whole menu bar panel: endpoint, usage, providers, models.
struct PanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            EndpointCard(model: model)
            UsageCard(model: model)
            ProviderGrid(model: model)
            ModelList(model: model)
            if let message = model.notice ?? model.problem {
                NoticeBar(message: message, isProblem: model.notice == nil)
            }
            Footer(model: model)
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { model.isPanelVisible = true }
        .onDisappear { model.isPanelVisible = false }
        .animation(.snappy(duration: 0.25), value: model.notice)
        .animation(.snappy(duration: 0.25), value: model.tiles)
    }
}

// MARK: - Shared styling

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// A button that swaps its icon for a checkmark for a moment after copying.
struct CopyButton: View {
    let text: String
    let model: AppModel
    @State private var copied = false

    var body: some View {
        Button {
            model.copy(text)
            withAnimation(.snappy) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.snappy) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26, height: 26)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy")
    }
}

// MARK: - Endpoint

struct EndpointCard: View {
    @Bindable var model: AppModel

    private var status: (label: String, color: Color) {
        switch model.server {
        case .running: ("Running", .green)
        case .starting: ("Starting…", .orange)
        case .stopping: ("Stopping…", .orange)
        case .stopped: ("Off", .secondary)
        }
    }

    var body: some View {
        Card {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 7, height: 7)
                            .shadow(color: status.color.opacity(0.7), radius: model.server == .running ? 3 : 0)
                        Text(status.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(OmniRoute.endpoint)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(model.server == .running ? .primary : .secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                CopyButton(text: OmniRoute.endpoint, model: model)
                Toggle("OmniRoute", isOn: Binding(
                    get: { model.server.isOn },
                    set: { model.setServer(on: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(model.server == .stopping)
                .help(model.server.isOn ? "Turn the endpoint off" : "Turn the endpoint on")
            }
        }
    }
}

// MARK: - Notices and footer

struct NoticeBar: View {
    let message: String
    let isProblem: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isProblem ? Color.orange : Color.green)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background((isProblem ? Color.orange : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct Footer: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack {
            Button {
                model.open(OmniRoute.dashboardURL)
            } label: {
                Label("Open Dashboard", systemImage: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.server != .running)

            Spacer()

            Menu {
                Toggle("Open at Login", isOn: Binding(get: { model.opensAtLogin }, set: { model.opensAtLogin = $0 }))
                Toggle("Import Local Logins Automatically", isOn: $model.autoImport)
                Button("Import Logins Now") { model.importLoginsNow() }
                    .disabled(model.server != .running)
                Divider()
                Button("Show OmniRoute Log") { NSWorkspace.shared.activateFileViewerSelecting([model.logURL]) }
                Divider()
                Button("Quit RouteBar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        .padding(.horizontal, 4)
    }
}
