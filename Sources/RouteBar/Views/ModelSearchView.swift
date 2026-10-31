import RouteBarKit
import SwiftUI

/// Searchable list of the models that active providers serve. Click to copy.
///
/// Closed, it is a single quiet bar, and no text field exists yet, so opening the
/// panel never puts the cursor in it. A click opens the search: the field and
/// the results unfold inside the same card, so nothing slides over the sections
/// around it. Only explicit actions open or close it (click, Esc, the close
/// button, hiding the panel). Hover never does, which used to make the list
/// flicker open and shut when the pointer sat on its edge.
struct ModelSearchView: View {
    @Bindable var model: AppModel
    @State private var isOpen = false
    @State private var query = ""
    @State private var selection = 0
    @State private var copiedID: String?
    @State private var hoveringList = false
    @FocusState private var searchFocused: Bool

    private let rowHeight: CGFloat = 26
    private let maxVisibleRows = 7

    private var results: [String] { Dashboard.filter(model.models, query: query) }
    private var canSearch: Bool { !model.models.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if isOpen {
                Divider().opacity(0.6)
                Group {
                    if results.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
                .onHover { hoveringList = $0 }
                .transition(.opacity)
            }
        }
        .background(.primary.opacity(isOpen ? 0.06 : 0.045), in: shape)
        .overlay(shape.strokeBorder(isOpen ? Theme.accent.opacity(0.55) : .primary.opacity(0.07)))
        .clipShape(shape)
        .animation(.snappy(duration: 0.2), value: isOpen)
        .animation(.snappy(duration: 0.16), value: results.count)
        .onChange(of: model.isPanelVisible) { _, visible in
            if !visible { close() }
        }
        .onChange(of: canSearch) { _, available in
            if !available { close() }
        }
        .onChange(of: query) { selection = 0 }
        #if DEBUG
            // `ROUTEBAR_SNAPSHOT_SEARCH=<query>` renders the search open, for visual checks.
            .onAppear {
                guard let search = ProcessInfo.processInfo.environment["ROUTEBAR_SNAPSHOT_SEARCH"] else { return }
                isOpen = true
                query = search
            }
        #endif
            // Clicking elsewhere in the panel ends an empty search, but never while
            // the pointer is on the list, where a click copies a row.
            .onChange(of: searchFocused) { _, focused in
                if !focused, query.isEmpty, !hoveringList { close() }
            }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOpen ? Theme.accent : .secondary)
                .frame(width: 14)
            if isOpen {
                field
            } else {
                opener
            }
            refreshButton
            if isOpen {
                IconButton(systemImage: "xmark", help: "Close (Esc)", size: 22) { close() }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 32)
    }

    /// Looks like the field but is a button, so nothing can focus it by itself.
    private var opener: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                Text(canSearch ? "Search \(model.models.count) models" : emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSearch)
        .help(canSearch ? "Search models and copy their exact names" : emptyMessage)
    }

    private var field: some View {
        HStack(spacing: 6) {
            TextField("Search models", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit(copySelection)
                .onExitCommand(perform: close)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
            if !query.isEmpty {
                Text("\(results.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        }
    }

    private var refreshButton: some View {
        IconButton(
            systemImage: "arrow.clockwise",
            help: "Refresh models from your providers",
            isBusy: model.isRefreshingModels,
            size: 22
        ) { model.refreshModelsNow() }
            .disabled(model.server != .running || !model.tiles.contains(where: \.isActive))
    }

    private var emptyMessage: String {
        switch model.server {
        case .running: model.tiles.contains(where: \.isActive) ? "Loading models…" : "Connect a provider to list its models"
        case .starting: "Starting OmniRoute…"
        case .stopping, .stopped: "Turn the endpoint on to list models"
        }
    }

    // MARK: Results

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element) { index, id in
                        ModelRow(id: id, isSelected: index == selection, copied: copiedID == id) { copy(id) }
                            .frame(height: rowHeight)
                            .id(id)
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.automatic)
            .frame(height: min(CGFloat(results.count), CGFloat(maxVisibleRows) + 0.5) * rowHeight + 8)
            .onChange(of: selection) { _, index in
                guard results.indices.contains(index) else { return }
                proxy.scrollTo(results[index])
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
            Text("No model matches “\(query)”").lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    // MARK: Actions

    private func open() {
        guard canSearch else { return }
        isOpen = true
        // The field exists only from this update on, so focus it on the next one.
        DispatchQueue.main.async { searchFocused = true }
    }

    private func close() {
        isOpen = false
        query = ""
        selection = 0
        hoveringList = false
        searchFocused = false
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        selection = min(max(selection + step, 0), results.count - 1)
        return .handled
    }

    private func copySelection() {
        guard results.indices.contains(selection) else { return }
        copy(results[selection])
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
    var isSelected = false
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
                } else if hovering || isSelected {
                    Image(systemName: isSelected && !hovering ? "return" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help("Copy \(id)")
    }

    private var background: Color {
        if hovering { return .primary.opacity(0.08) }
        return isSelected ? Theme.accent.opacity(0.12) : .clear
    }
}
