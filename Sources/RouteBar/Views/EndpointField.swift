import RouteBarKit
import SwiftUI

/// The base URL third-party apps need, with a one-click copy. For a server on
/// this Mac it follows the Endpoint setting: `localhost`, the LAN address when
/// OmniRoute answers there, or the public Cloudflare tunnel address.
struct EndpointField: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.server == .running ? Theme.accent : Color.secondary)
            if model.isTunnelPending {
                Text("Opening public address…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ProgressView().controlSize(.small).frame(width: 24, height: 24)
            } else {
                Text(model.endpoint)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.server == .running ? .primary : .secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                CopyButton(text: model.endpoint, model: model)
            }
        }
        .surface(padding: 8)
        .help(help)
    }

    private var icon: String {
        if model.isRemote { return "network" }
        return model.tunnelRoot != nil ? "globe" : "link"
    }

    private var help: String {
        if model.isRemote { return "OmniRoute on \(model.serverLabel). Apps need one of its API keys." }
        let host = model.preferences.endpointHost
        if host == .tunnel, model.tunnelRoot != nil {
            return "Works from anywhere through a Cloudflare quick tunnel. Change the address in Settings."
        }
        if host == .tunnel, model.isTunnelPending { return "Cloudflare is opening a public address for OmniRoute." }
        if model.lanAddress != nil, host != .localhost {
            return "Works on this Mac and other devices on your network. Change the address in Settings."
        }
        return "Works on this Mac. Change the address in Settings."
    }
}
