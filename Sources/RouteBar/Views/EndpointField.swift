import RouteBarKit
import SwiftUI

/// The base URL third-party apps need, with a one-click copy. For a server on
/// this Mac it shows the LAN address when OmniRoute answers there, so the same
/// URL works from other devices, and `localhost` otherwise.
struct EndpointField: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isRemote ? "network" : "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.server == .running ? Theme.accent : Color.secondary)
            Text(model.endpoint)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(model.server == .running ? .primary : .secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            CopyButton(text: model.endpoint, model: model)
        }
        .surface(padding: 8)
        .help(help)
    }

    private var help: String {
        if model.isRemote { return "OmniRoute on \(model.serverLabel). Apps need one of its API keys." }
        if model.lanAddress != nil, model.preferences.endpointHost == .network {
            return "Works on this Mac and other devices on your network. Other devices need an OmniRoute API key."
        }
        return "Works on this Mac. Change the address in Settings."
    }
}
