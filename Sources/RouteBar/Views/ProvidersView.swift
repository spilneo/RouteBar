import RouteBarKit
import SwiftUI

/// Connected providers as tiles sharing the full width: logo, name, and a thin
/// meter per subscription window (for example 5h and 7d) when OmniRoute knows it.
struct ProvidersView: View {
    @Bindable var model: AppModel
    private let maxColumns = 4

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(max(model.tiles.count, 1), maxColumns))
        LazyVGrid(columns: columns, spacing: 8) {
            if model.tiles.isEmpty {
                AddProviderTile(enabled: model.server == .running) { model.open(OmniRoute.providersURL) }
            } else {
                ForEach(model.tiles) { tile in
                    ProviderTileView(tile: tile, wide: model.tiles.count == 1) { model.open(OmniRoute.providersURL) }
                }
            }
        }
    }
}

struct ProviderTileView: View {
    let tile: ProviderTile
    /// A single provider gets a horizontal layout with labelled meters.
    let wide: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if wide { wideLayout } else { compactLayout }
            }
            .surface(padding: 10, highlighted: hovering)
            .opacity(tile.isActive ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }

    private var wideLayout: some View {
        HStack(spacing: 10) {
            ProviderLogo(id: tile.id, name: tile.name).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(tile.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if tile.quotas.isEmpty {
                    Text(tile.isActive ? "Connected" : "No active connection")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tile.quotas) { QuotaMeter(window: $0, showsValue: true) }
                }
            }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 6) {
            ProviderLogo(id: tile.id, name: tile.name).frame(width: 22, height: 22)
            Text(tile.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            if !tile.quotas.isEmpty {
                VStack(spacing: 3) {
                    ForEach(tile.quotas.prefix(2)) { QuotaMeter(window: $0, showsValue: false) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var helpText: String {
        guard tile.isActive else { return "\(tile.name) has no active connection" }
        let lines = tile.quotas.map { window -> String in
            var line = "\(window.label): \(Int(window.usedPercent.rounded()))% used"
            if let reset = window.resetsAt { line += ", resets \(reset.formatted(.relative(presentation: .named)))" }
            return line
        }
        return ([tile.name] + lines).joined(separator: "\n")
    }
}

/// A thin capsule showing how much of a limit window is used.
struct QuotaMeter: View {
    let window: QuotaWindow
    let showsValue: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(window.label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.1))
                    Capsule()
                        .fill(Theme.color(for: window.level))
                        .frame(width: max(proxy.size.width * window.usedPercent / 100, window.usedPercent > 0 ? 3 : 0))
                }
            }
            .frame(height: 4)
            if showsValue {
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(window.level == .normal ? Color.secondary : Theme.color(for: window.level))
                    .frame(width: 30, alignment: .trailing)
                if let reset = window.resetsAt {
                    Text(Dashboard.countdown(to: reset))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
        .animation(.snappy, value: window.usedPercent)
    }
}

struct ProviderLogo: View {
    let id: String
    let name: String
    private var icons = ProviderIcons.shared

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    var body: some View {
        if let icon = icons.icon(for: id) {
            if icon.isMonochrome {
                Image(nsImage: icon.image).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(.primary)
            } else {
                Image(nsImage: icon.image).resizable().scaledToFit()
            }
        } else {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

struct AddProviderTile: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add a provider in the dashboard")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
