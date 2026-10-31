import RouteBarKit
import SwiftUI

/// One flat accent colour, the brand indigo of the app icon (`logo.svg`)
/// unless another preset is picked in Settings, and a few metrics. No gradients anywhere.
@MainActor
enum Theme {
    static var accent: Color { Appearance.shared.accent.color }
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
    /// Side of the square hit area. Smaller sizes fit inside fields.
    var size: CGFloat = 28
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.46, weight: .medium))
                        .symbolVariant(isOn == true ? .fill : .none)
                }
            }
            .foregroundStyle(isOn == true ? Theme.accent : Color.secondary)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: size * 0.29))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 && isEnabled }
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

/// Flat, rounded text buttons that match the panel instead of the stock bezel.
///
/// `.prominent` is filled with the accent for the one action that moves things
/// forward, `.secondary` is a quiet tinted fill, and `.destructive` uses red.
struct PanelButtonStyle: ButtonStyle {
    enum Kind { case prominent, secondary, destructive }

    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: kind == .prominent ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .frame(minWidth: 56, minHeight: 24)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(border))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .animation(.snappy(duration: 0.12), value: hovering)
                .onHover { hovering = $0 && isEnabled }
        }

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7, style: .continuous) }

        private var tint: Color { kind == .destructive ? .red : Theme.accent }

        private var foreground: Color {
            switch kind {
            case .prominent: .white
            case .secondary: .primary
            case .destructive: .red
            }
        }

        private var fill: Color {
            let boost = configuration.isPressed ? 0.12 : hovering ? 0.06 : 0
            switch kind {
            case .prominent: return tint.opacity(configuration.isPressed ? 0.8 : hovering ? 0.9 : 1)
            case .secondary: return Color.primary.opacity(0.07 + boost)
            case .destructive: return Color.red.opacity(0.1 + boost)
            }
        }

        private var border: Color {
            kind == .prominent ? .clear : Color.primary.opacity(0.08)
        }
    }
}

extension ButtonStyle where Self == PanelButtonStyle {
    static var panel: PanelButtonStyle { PanelButtonStyle() }
    static func panel(_ kind: PanelButtonStyle.Kind) -> PanelButtonStyle { PanelButtonStyle(kind: kind) }
}

/// A labelled "‹ Back" control for screens shown in place of the panel.
struct BackButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text("Back").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .frame(height: 26)
            .background(Theme.accent.opacity(hovering ? 0.16 : 0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Back to RouteBar (Esc)")
        .accessibilityLabel("Back")
    }
}
