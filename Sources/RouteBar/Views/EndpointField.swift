import RouteBarKit
import SwiftUI

/// The base URL third-party apps need, with a one-click copy.
struct EndpointField: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.server == .running ? Theme.accent : Color.secondary)
            Text(OmniRoute.endpoint)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(model.server == .running ? .primary : .secondary)
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 0)
            CopyButton(text: OmniRoute.endpoint, model: model)
        }
        .surface(padding: 8)
        .padding(.leading, 0)
    }
}
