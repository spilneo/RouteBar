import RouteBarKit
import SwiftUI

/// One flat brand colour, shared with the app icon (`logo.svg`), and a few
/// metrics. No gradients anywhere.
enum Theme {
    static let accent = Color(red: 0x5e / 255, green: 0x5c / 255, blue: 0xe6 / 255)
    static let radius: CGFloat = 12
    static let width: CGFloat = 340

    static func color(for level: QuotaWindow.Level) -> Color {
        switch level {
        case .normal: accent
        case .high: .orange
        case .critical: .red
        }
    }
}

/// The quiet rounded panel every section sits on.
struct Surface: ViewModifier {
    var padding: CGFloat = 12
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(highlighted ? 0.08 : 0.045), in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.07)))
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous) }
}

extension View {
    func surface(padding: CGFloat = 12, highlighted: Bool = false) -> some View {
        modifier(Surface(padding: padding, highlighted: highlighted))
    }
}

/// A compact icon-only button. With `isOn` it acts as a toggle and tints when on.
struct IconButton: View {
    let systemImage: String
    let help: String
    var isOn: Bool?
    var isBusy = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .symbolVariant(isOn == true ? .fill : .none)
                }
            }
            .foregroundStyle(isOn == true ? Theme.accent : Color.secondary)
            .frame(width: 28, height: 28)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var background: Color {
        if isOn == true { return Theme.accent.opacity(hovering ? 0.22 : 0.14) }
        return .primary.opacity(hovering ? 0.08 : 0)
    }
}

/// Copies text and briefly swaps its icon for a checkmark.
struct CopyButton: View {
    let text: String
    let model: AppModel
    @State private var copied = false

    var body: some View {
        Button {
            model.copy(text)
            withAnimation(.snappy) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.snappy) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy")
    }
}

struct NoticeBar: View {
    let message: String
    let isProblem: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isProblem ? Color.orange : Color.green)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background((isProblem ? Color.orange : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
