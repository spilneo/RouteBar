import RouteBarKit
import SwiftUI

/// Searchable list of the models that active providers serve. Click to copy.
struct ModelList: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var copiedID: String?
    @FocusState private var searchFocused: Bool

    private var results: [String] { Dashboard.filter(model.models, query: query) }

    var body: some View {
        VStack(spacing: 6) {
            searchField
            Group {
                if model.models.isEmpty {
                    emptyState(emptyMessage)
                } else if results.isEmpty {
                    emptyState("No model matches “\(query)”")
                } else {
                    list
                }
            }
            .frame(height: 176)
        }
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
            TextField("Search \(model.models.count) models", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit { if let first = results.first { copy(first) } }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
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
