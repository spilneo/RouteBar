import RouteBarKit
import SwiftUI

/// Connected providers as tiles sharing the full width: logo, name, and a thin
/// meter per subscription window (for example 5h and 7d) when OmniRoute knows it.
///
/// Several accounts of one provider share a tile with a count badge, and the
/// meters show the busiest account. Clicking a tile unfolds every account with
/// its own limits. More than two rows of providers scroll inside a fixed height.
struct ProvidersView: View {
    @Bindable var model: AppModel
    private var expanded: String? {
        get { model.expandedProvider }
        nonmutating set { model.expandedProvider = newValue }
    }

    private let maxColumns = 4
    private let maxRows = 2

    private var expandedTile: ProviderTile? { model.tiles.first { $0.id == expanded } }

    var body: some View {
        VStack(spacing: 8) {
            if model.tiles.isEmpty {
                AddProviderTile(enabled: model.server == .running) { model.open(model.providersURL) }
            } else if model.tiles.count == 1, let tile = model.tiles.first {
                SingleProviderView(tile: tile) { model.open(model.providersURL) }
            } else {
                grid
                if let tile = expandedTile {
                    AccountsPanel(tile: tile) { model.open(model.providersURL) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: expanded)
        .onChange(of: model.tiles.map(\.id)) { _, ids in
            if let expanded, !ids.contains(expanded) { self.expanded = nil }
        }
        .onChange(of: model.isPanelVisible) { _, visible in
            if !visible { expanded = nil }
        }
    }

    /// When any tile shows meters, the others keep the same height so rows line up.
    private var reservesMeters: Bool { model.tiles.contains { !$0.quotas.isEmpty } }

    @ViewBuilder private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(model.tiles.count, maxColumns))
        let tiles = LazyVGrid(columns: columns, spacing: 8) {
            ForEach(model.tiles) { tile in
                ProviderTileView(tile: tile, isSelected: expanded == tile.id, reservesMeters: reservesMeters) {
                    expanded = expanded == tile.id ? nil : tile.id
                }
            }
        }
        if model.tiles.count > maxColumns * maxRows {
            ScrollView {
                tiles.padding(.bottom, 4)
            }
            .scrollIndicators(.automatic)
            .frame(height: 212) // two full rows and a peek at the third
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        } else {
            tiles
        }
    }
}

/// The only provider gets a wide tile with labelled meters, and its accounts
/// listed inline when there are several.
struct SingleProviderView: View {
    let tile: ProviderTile
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProviderLogo(id: tile.id, name: tile.name).frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(tile.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            if tile.accounts.count > 1 { AccountCountBadge(tile: tile) }
                        }
                        if tile.accounts.count > 1 {
                            Text("\(tile.activeAccounts) of \(tile.accounts.count) accounts active")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        } else if tile.quotas.isEmpty {
                            Text(tile.isActive ? "Connected" : "No active connection")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(tile.quotas) { QuotaMeter(window: $0, showsValue: true) }
                        }
                    }
                }
                if tile.accounts.count > 1 {
                    AccountList(accounts: tile.accounts)
                }
            }
            .surface(padding: 10, highlighted: hovering)
            .opacity(tile.isActive ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Manage \(tile.name) in the dashboard")
    }
}

struct ProviderTileView: View {
    let tile: ProviderTile
    let isSelected: Bool
    var reservesMeters = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
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
                } else if reservesMeters {
                    VStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { _ in
                            QuotaMeter(window: QuotaWindow(label: "7d", usedPercent: 0, resetsAt: nil), showsValue: false)
                        }
                    }
                    .hidden()
                }
            }
            .frame(maxWidth: .infinity)
            .surface(padding: 10, highlighted: hovering || isSelected)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.accent.opacity(0.7))
                }
            }
            .overlay(alignment: .topTrailing) {
                if tile.accounts.count > 1 { AccountCountBadge(tile: tile).padding(5) }
            }
            .opacity(tile.isActive ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var helpText: String {
        guard tile.isActive else { return "\(tile.name) has no active connection. Click for details." }
        var lines = [tile.accounts.count > 1 ? "\(tile.name): \(tile.activeAccounts) of \(tile.accounts.count) accounts active" : tile.name]
        lines += tile.quotas.map { window -> String in
            var line = "\(window.label): \(Int(window.usedPercent.rounded()))% used"
            if tile.accounts.count > 1 { line += " by the busiest account" }
            if let reset = window.resetsAt { line += ", resets \(reset.formatted(.relative(presentation: .named)))" }
            return line
        }
        lines.append("Click to see every account")
        return lines.joined(separator: "\n")
    }
}

/// How many accounts a provider has, shown when there is more than one.
struct AccountCountBadge: View {
    let tile: ProviderTile

    var body: some View {
        Text("\(tile.accounts.count)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 14)
            .background(Theme.accent.opacity(0.15), in: Capsule())
            .accessibilityLabel("\(tile.accounts.count) accounts")
    }
}

/// The unfolded tile: every account of one provider with its own limits.
struct AccountsPanel: View {
    let tile: ProviderTile
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderLogo(id: tile.id, name: tile.name).frame(width: 16, height: 16)
                Text(tile.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(tile.accounts.count == 1 ? "1 account" : "\(tile.activeAccounts) of \(tile.accounts.count) active")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                IconButton(systemImage: "arrow.up.forward.app", help: "Manage \(tile.name) in the dashboard", action: openDashboard)
                    .frame(height: 18)
            }
            AccountList(accounts: tile.accounts)
        }
        .surface(padding: 10)
    }
}

/// Account rows, scrolling past a handful so many logins never stretch the panel.
struct AccountList: View {
    let accounts: [ProviderAccount]
    private let visibleRows = 4

    var body: some View {
        if accounts.count > visibleRows {
            ScrollView {
                rows
            }
            .scrollIndicators(.automatic)
            .frame(height: 150)
        } else {
            rows
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 7) {
            ForEach(accounts) { AccountRow(account: $0) }
        }
    }
}

struct AccountRow: View {
    let account: ProviderAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(account.isActive ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(account.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(account.isActive ? .primary : .secondary)
                Spacer(minLength: 0)
                if !account.isActive {
                    Text("Inactive").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            ForEach(account.quotas) { QuotaMeter(window: $0, showsValue: true) }
                .padding(.leading, 12)
        }
        .help(account.name)
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
