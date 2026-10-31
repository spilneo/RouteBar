import RouteBarKit
import SwiftUI

/// RouteBar's preferences, shown in place of the panel: appearance, the
/// endpoint address, which OmniRoute to manage, and general behaviour.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable private var appearance = Appearance.shared
    @State private var editingRemote = false

    init(model: AppModel) {
        self.model = model
    }

    private var showsRemoteForm: Bool { editingRemote || (model.preferences.remote == nil && wantsRemote) }
    @State private var wantsRemote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            section("Appearance", icon: "paintpalette") {
                row("Accent") { AccentPicker(selection: $appearance.accent) }
                Divider().opacity(0.5)
                row("Translucent panel", detail: "Off uses a solid background") {
                    Toggle("Translucent panel", isOn: $appearance.isTranslucent).switchStyle()
                }
            }
            section("Server", icon: "server.rack") { serverSection }
            if !model.isRemote {
                section("Endpoint", icon: "link") { endpointSection }
            }
            section("General", icon: "gearshape") { generalSection }
            footer
        }
        .onAppear { wantsRemote = model.preferences.usesRemote }
        .task { await model.refreshRequiresAPIKey(force: true) }
    }

    // MARK: Sections

    private var header: some View {
        ZStack {
            Text("Settings").font(.system(size: 13, weight: .semibold))
            HStack {
                BackButton {
                    withAnimation(.snappy(duration: 0.22)) { model.showsSettings = false }
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder private var serverSection: some View {
        SegmentedPicker(selection: $wantsRemote, options: [(false, "This Mac"), (true, "Remote server")])
            .onChange(of: wantsRemote) { _, remote in selectTarget(remote) }

        if !wantsRemote {
            caption("RouteBar starts and stops OmniRoute on this Mac on port \(OmniRoute.port).")
        } else if showsRemoteForm {
            RemoteSignInForm(model: model, initialAddress: model.preferences.remote.map { ServerAddress.label(for: $0.url) } ?? "") {
                editingRemote = false
                wantsRemote = model.preferences.usesRemote
            } onCancel: {
                editingRemote = false
                wantsRemote = model.preferences.usesRemote
            }
        } else if let remote = model.preferences.remote {
            remoteSummary(remote)
        }
    }

    private func remoteSummary(_ remote: RemoteServer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(state: model.server, isBusy: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ServerAddress.label(for: remote.url))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(remoteDetail(remote)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Spacer()
                Button("Forget") {
                    model.forgetRemote()
                    wantsRemote = false
                }
                .buttonStyle(.panel(.destructive))
                .help("Return to this Mac and remove the access token from the Keychain")
                Button("Sign In Again") { editingRemote = true }
                    .buttonStyle(.panel)
            }
            caption("Status, usage, providers and models come from this server. Stopping it works from here, "
                + "starting it has to happen on that machine.")
        }
    }

    private func remoteDetail(_ remote: RemoteServer) -> String {
        var parts: [String] = []
        if let name = remote.tokenName { parts.append(name) }
        if let scope = remote.scope { parts.append("\(scope) access") }
        return parts.isEmpty ? "Signed in" : parts.joined(separator: " · ")
    }

    @ViewBuilder private var endpointSection: some View {
        let host = model.preferences.endpointHost
        SegmentedPicker(
            selection: Binding(get: { model.preferences.endpointHost }, set: { model.setEndpointHost($0) }),
            options: EndpointHost.allCases.map { ($0, $0.label) }
        )
        caption(endpointCaption)
        if host == .tunnel, let error = model.tunnelError, !model.isChangingTunnel {
            Text("The tunnel did not open: \(error)")
                .font(.system(size: 10.5))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        if host != .localhost, model.server == .running {
            Divider().opacity(0.5)
            row("Require an API key", detail: "For every app, including on this Mac") {
                Toggle("Require an API key", isOn: Binding(
                    get: { model.requiresAPIKey ?? false },
                    set: { model.setRequiresAPIKey($0) }
                ))
                .switchStyle()
                .disabled(model.requiresAPIKey == nil)
            }
            if model.requiresAPIKey == false {
                Text(host == .tunnel
                    ? "Anyone who has the address can use your subscriptions. Turn this on and give your apps an OmniRoute API key."
                    : "Any device on your network can use your subscriptions.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(host == .tunnel ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.requiresAPIKey == true { apiKeyList }
        }
    }

    /// The server's keys with a copy button each, so apps can be set up without the dashboard.
    @ViewBuilder private var apiKeyList: some View {
        let state = model.apiKeyState
        VStack(alignment: .leading, spacing: 4) {
            ForEach(state.keys.prefix(6)) { key in
                APIKeyRow(info: key, canCopy: state.copyable.contains(key.id), model: model)
            }
        }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            caption(state.keys.isEmpty
                ? "Create a key and paste it into your apps as their API key."
                : state.allowsReveal
                ? "Paste a key into your apps as their API key."
                : "Keys made or copied in RouteBar can be copied here. OmniRoute hides the others unless API Key Reveal is on.")
            Spacer(minLength: 4)
            Button {
                model.createAPIKey()
            } label: {
                if state.isCreating { ProgressView().controlSize(.mini) } else { Text("New Key") }
            }
            .buttonStyle(.panel)
            .disabled(state.isCreating)
            .help("Create an API key that may use every model, and copy it")
        }
    }

    private var endpointCaption: String {
        switch model.preferences.endpointHost {
        case .localhost:
            return "localhost works only for apps on this Mac."
        case .network:
            if let address = model.lanAddress { return "\(address) works for apps on this Mac and on your network." }
            if model.server != .running { return "The network address appears once OmniRoute is running." }
            return "No network address answers right now, so localhost is shown."
        case .tunnel:
            if let host = model.tunnelRoot?.host {
                return "\(host) works from anywhere through a free Cloudflare quick tunnel. "
                    + "The address changes each time the tunnel opens."
            }
            if model.server != .running { return "A public Cloudflare address opens once OmniRoute is running." }
            if model.isTunnelPending { return "Opening a Cloudflare quick tunnel. This can take up to half a minute." }
            return "A free Cloudflare quick tunnel gives OmniRoute a public https address. The network address is shown until it opens."
        }
    }

    @ViewBuilder private var generalSection: some View {
        @Bindable var preferences = model.preferences
        row("Import logins automatically", detail: "Connect AI tools signed in on this Mac") {
            Toggle("Import logins automatically", isOn: $preferences.autoImport)
                .switchStyle()
        }
        Divider().opacity(0.5)
        row("Open at login") {
            Toggle("Open at login", isOn: Binding(get: { preferences.opensAtLogin }, set: { enabled in
                preferences.setOpensAtLogin(enabled)
                if let error = preferences.loginItemError { model.show("Could not change Open at Login: \(error)") }
            }))
            .switchStyle()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let message = model.notice ?? model.problem {
                NoticeBar(message: message, isProblem: model.notice == nil)
            }
            BrandMark(opacity: 0.38)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
    }

    private func selectTarget(_ remote: Bool) {
        editingRemote = false
        if !remote {
            model.useRemote(false)
        } else if model.preferences.remote != nil {
            model.useRemote(true)
        }
    }

    // MARK: Building blocks

    private func section(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title.uppercased()).tracking(0.4)
            } icon: {
                Image(systemName: icon).foregroundStyle(Theme.accent)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .labelStyle(SectionLabelStyle())
            .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content() }
                .surface(padding: 10)
        }
    }

    private func row(_ title: String, detail: String? = nil, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                if let detail { Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            control()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Preset colours as swatches. Click one to restyle the panel.
struct AccentPicker: View {
    @Binding var selection: Appearance.Accent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Appearance.Accent.allCases) { accent in
                Button {
                    selection = accent
                } label: {
                    ZStack {
                        Circle().fill(accent.color).frame(width: 16, height: 16)
                        if selection == accent {
                            Circle().strokeBorder(accent.color, lineWidth: 1.5).frame(width: 22, height: 22)
                            Image(systemName: "checkmark").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(accent.name)
                .accessibilityLabel(accent.name)
                .accessibilityAddTraits(selection == accent ? .isSelected : [])
            }
        }
    }
}

@MainActor
private extension Toggle {
    func switchStyle() -> some View {
        toggleStyle(.panelSwitch).labelsHidden()
    }
}

/// A small tinted icon before a section title.
private struct SectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 9.5, weight: .semibold))
            configuration.title
        }
    }
}

/// A flat text field whose border takes the accent colour while it is focused.
struct PanelTextField: View {
    let prompt: String
    @Binding var text: String
    var secure = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField(prompt, text: $text) } else { TextField(prompt, text: $text) }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12, design: secure ? .default : .monospaced))
        .focused($focused)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.primary.opacity(focused ? 0.075 : 0.055), in: shape)
        .overlay(shape.strokeBorder(focused ? Theme.accent.opacity(0.6) : .primary.opacity(0.07)))
        .animation(.snappy(duration: 0.15), value: focused)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7, style: .continuous) }
}
