import RouteBarKit
import SwiftUI

/// Searchable list of the models that active providers serve. Click to copy.
///
/// Collapsed to the search field until it is focused, so the panel stays short.
/// The list also stays open while it holds a query or the pointer is over it,
/// so clicking a row to copy it never collapses the list under the cursor.
struct ModelSearchView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var copiedID: String?
    @State private var hoveringList = false
    /// Set by a click into the field. macOS may focus the field by itself when
    /// the panel opens, and that alone must not unfold the list.
    @State private var clickedIntoSearch = false
    @State private var panelShownAt = Date.distantPast
    @FocusState private var searchFocused: Bool

    private var results: [String] { Dashboard.filter(model.models, query: query) }
    private var isExpanded: Bool {
        !model.models.isEmpty && ((searchFocused && clickedIntoSearch) || !query.isEmpty || hoveringList)
    }

    var body: some View {
        VStack(spacing: 6) {
            searchField
            if isExpanded {
                Group {
                    if results.isEmpty {
                        emptyState("No model matches “\(query)”")
                    } else {
                        list
                    }
                }
                .frame(height: 176)
                .onHover { hoveringList = $0 }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.22), value: isExpanded)
        // macOS focuses the first text field when the panel opens. Undo that so
        // the list only opens when the user clicks into the search field.
        .onChange(of: model.isPanelVisible, initial: true) { _, visible in
            guard visible else { return collapse() }
            panelShownAt = Date()
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                searchFocused = false
            }
        }
        // Focus that arrives well after the panel opened comes from the user.
        .onChange(of: searchFocused) { _, focused in
            if !focused {
                clickedIntoSearch = false
            } else if Date().timeIntervalSince(panelShownAt) > 0.3 {
                clickedIntoSearch = true
            }
        }
    }

    private func collapse() {
        query = ""
        hoveringList = false
        clickedIntoSearch = false
        searchFocused = false
    }

    private var emptyMessage: String {
        switch model.server {
        case .running: model.tiles.contains(where: \.isActive) ? "Loading models…" : "Connect a provider to list its models"
        case .starting: "Starting OmniRoute…"
        case .stopping, .stopped: "Turn the endpoint on to list models"
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(model.models.isEmpty ? emptyMessage : "Search \(model.models.count) models", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .disabled(model.models.isEmpty)
                .onSubmit { if let first = results.first { copy(first) } }
                .onExitCommand { collapse() }
                .simultaneousGesture(TapGesture().onEnded { clickedIntoSearch = true })
            if isExpanded {
                Button {
                    collapse()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(searchFocused ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1)
        )
        .help("Press Return to copy the first result")
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(results, id: \.self) { id in
                    ModelRow(id: id, copied: copiedID == id) { copy(id) }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.automatic)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 18))
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ id: String) {
        model.copy(id)
        withAnimation(.snappy) { copiedID = id }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == id { withAnimation(.snappy) { copiedID = nil } }
        }
    }
}

struct ModelRow: View {
    let id: String
    let copied: Bool
    let action: () -> Void
    @State private var hovering = false

    private var parts: (prefix: String, name: String) {
        guard let slash = id.firstIndex(of: "/") else { return ("", id) }
        return (String(id[...slash]), String(id[id.index(after: slash)...]))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(parts.prefix).foregroundStyle(.tertiary)
                Text(parts.name).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                } else if hovering {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.primary.opacity(hovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy \(id)")
    }
}
