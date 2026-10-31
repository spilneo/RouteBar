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
            section("Appearance") {
                row("Accent") { AccentPicker(selection: $appearance.accent) }
                Divider().opacity(0.5)
                row("Translucent panel", detail: "Off uses a solid background") {
                    Toggle("Translucent panel", isOn: $appearance.isTranslucent).switchStyle()
                }
            }
            section("Server") { serverSection }
            if !model.isRemote {
                section("Endpoint") { endpointSection }
            }
            section("General") { generalSection }
            footer
        }
        .onAppear { wantsRemote = model.preferences.usesRemote }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 6) {
            IconButton(systemImage: "chevron.left", help: "Back") {
                withAnimation(.snappy(duration: 0.22)) { model.showsSettings = false }
            }
            .keyboardShortcut(.cancelAction)
            Text("Settings").font(.system(size: 13, weight: .semibold))
            Spacer()
        }
    }

    @ViewBuilder private var serverSection: some View {
        Picker("Server", selection: Binding(get: { wantsRemote }, set: selectTarget)) {
            Text("This Mac").tag(false)
            Text("Remote server").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

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
                Button("Sign In Again") { editingRemote = true }.controlSize(.small)
                Button("Forget") {
                    model.forgetRemote()
                    wantsRemote = false
                }
                .controlSize(.small)
                .help("Return to this Mac and remove the access token from the Keychain")
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
        let preferences = model.preferences
        Picker("Address", selection: Binding(get: { preferences.endpointHost }, set: { preferences.endpointHost = $0 })) {
            ForEach(EndpointHost.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        caption(endpointCaption)
    }

    private var endpointCaption: String {
        guard model.preferences.endpointHost == .network else { return "Works only for apps on this Mac." }
        if let address = model.lanAddress {
            return "\(address) works for apps on this Mac and on your network. Other devices need an OmniRoute API key."
        }
        if model.server != .running { return "The network address appears once OmniRoute is running." }
        return "No network address answers right now, so localhost is shown."
    }

    @ViewBuilder private var generalSection: some View {
        let preferences = model.preferences
        row("Import logins automatically", detail: "Connect AI tools signed in on this Mac") {
            Toggle("Import logins automatically", isOn: Binding(get: { preferences.autoImport }, set: { preferences.autoImport = $0 }))
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return HStack {
            Text(version.map { "RouteBar \($0)" } ?? "RouteBar")
            Spacer()
            if let message = model.notice ?? model.problem {
                Text(message).lineLimit(1).truncationMode(.tail)
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }

    private func selectTarget(_ remote: Bool) {
        wantsRemote = remote
        editingRemote = false
        if !remote {
            model.useRemote(false)
        } else if model.preferences.remote != nil {
            model.useRemote(true)
        }
    }

    // MARK: Building blocks

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) { content() }
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

/// Address and credential for a remote OmniRoute, checked before anything is saved.
struct RemoteSignInForm: View {
    enum Method: String, CaseIterable, Identifiable {
        case password = "Password"
        case token = "Access token"
        var id: String { rawValue }
    }

    let model: AppModel
    let onDone: () -> Void
    let onCancel: () -> Void
    @State private var address: String
    @State private var method = Method.password
    @State private var secret = ""
    @State private var isConnecting = false
    @State private var error: String?

    init(model: AppModel, initialAddress: String, onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        self.onCancel = onCancel
        _address = State(initialValue: initialAddress)
    }

    private var url: URL? { ServerAddress.normalize(address) }
    private var canConnect: Bool { url != nil && !secret.isEmpty && !isConnecting }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Host or URL, e.g. 192.168.1.20", text: $address, secure: false)
            Picker("Sign in with", selection: $method) {
                ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            field(method == .password ? "Management password" : "oma_… access token", text: $secret, secure: true)
                .onSubmit(connect)

            if let error {
                Text(error).font(.system(size: 10.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(hint).font(.system(size: 10.5)).foregroundStyle(warnsAboutHTTP ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).controlSize(.small)
                Button(action: connect) {
                    if isConnecting { ProgressView().controlSize(.mini) } else { Text("Connect") }
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConnect)
            }
        }
        .onChange(of: method) { secret = ""; error = nil }
    }

    private var warnsAboutHTTP: Bool {
        guard let url else { return false }
        return url.scheme == "http" && !ServerAddress.isPrivate(url)
    }

    private var hint: String {
        if warnsAboutHTTP { return "This address is public and uses http, so the password and token travel unencrypted. Prefer https." }
        return method == .password
            ? "The password is used once to create an access token for RouteBar and is not stored."
            : "Create one on the server with `omniroute tokens create`. It is kept in your Keychain."
    }

    private func field(_ prompt: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure { SecureField(prompt, text: text) } else { TextField(prompt, text: text) }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12, design: secure ? .default : .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func connect() {
        guard canConnect else { return }
        isConnecting = true
        error = nil
        let credential: AppModel.RemoteCredential = method == .password ? .password(secret) : .token(secret)
        Task {
            defer { isConnecting = false }
            do {
                try await model.connectRemote(address: address, credential: credential)
                secret = ""
                onDone()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private extension Toggle {
    func switchStyle() -> some View {
        toggleStyle(.switch).labelsHidden().controlSize(.mini)
    }
}
