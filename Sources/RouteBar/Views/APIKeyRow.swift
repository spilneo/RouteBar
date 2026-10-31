import RouteBarKit
import SwiftUI

/// One API key: its name, the masked value and a copy button that fetches the full key.
struct APIKeyRow: View {
    let info: APIKeyInfo
    let canCopy: Bool
    let model: AppModel
    @State private var copied = false
    @State private var isCopying = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(info.name ?? "API key").font(.system(size: 11.5)).lineLimit(1)
                if let masked = info.key {
                    Text(masked).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button(action: copyKey) {
                Image(systemName: copied ? "checkmark" : "square.on.square")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(copied ? Color.green : canCopy ? Color.secondary : Color.secondary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCopying)
            .help(canCopy ? "Copy the full key" : "OmniRoute hides this key. Turn on API Key Reveal in its dashboard, or create a new key.")
            .accessibilityLabel("Copy \(info.name ?? "API key")")
        }
    }

    private func copyKey() {
        isCopying = true
        Task {
            let done = await model.copyAPIKey(info)
            isCopying = false
            guard done else { return }
            withAnimation(.snappy) { copied = true }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) { copied = false }
        }
    }
}
