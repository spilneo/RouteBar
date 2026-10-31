import RouteBarKit
import SwiftUI

/// Connected providers as icon tiles that share the full panel width.
struct ProviderGrid: View {
    @Bindable var model: AppModel
    private let maxColumns = 4

    var body: some View {
        let count = max(model.tiles.count, 1)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(count, maxColumns))
        LazyVGrid(columns: columns, spacing: 8) {
            if model.tiles.isEmpty {
                AddProviderTile(enabled: model.server == .running) { model.open(OmniRoute.providersURL) }
            } else {
                ForEach(model.tiles) { tile in
                    ProviderTileView(tile: tile) { model.open(OmniRoute.providersURL) }
                }
            }
        }
    }
}

struct ProviderTileView: View {
    let tile: ProviderTile
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ProviderLogo(id: tile.id, name: tile.name)
                    .frame(width: 24, height: 24)
                Text(tile.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(.primary.opacity(hovering ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
            .opacity(tile.isActive ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tile.isActive ? tile.name : "\(tile.name) has no active connection")
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
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

struct AddProviderTile: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24, height: 24)
                Text("Add a provider")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
