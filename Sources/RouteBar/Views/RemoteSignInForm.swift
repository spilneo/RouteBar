import RouteBarKit
import SwiftUI

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
            SegmentedPicker(selection: $method, options: Method.allCases.map { ($0, $0.rawValue) })
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
                Button("Cancel", action: onCancel)
                    .buttonStyle(.panel)
                Button(action: connect) {
                    if isConnecting { ProgressView().controlSize(.mini).tint(.white) } else { Text("Connect") }
                }
                .buttonStyle(.panel(.prominent))
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
        PanelTextField(prompt: prompt, text: text, secure: secure)
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
