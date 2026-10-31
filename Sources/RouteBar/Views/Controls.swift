import SwiftUI

/// A flat switch in the accent colour, in place of the stock macOS switch.
struct PanelSwitchStyle: ToggleStyle {
    var width: CGFloat = 30
    var height: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration, width: width, height: height)
    }

    private struct SwitchBody: View {
        let configuration: Configuration
        let width: CGFloat
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let isOn = configuration.isOn
            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary.opacity(hovering ? 0.2 : 0.14)))
                    Capsule().strokeBorder(.primary.opacity(isOn ? 0 : 0.06))
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                        .padding(2)
                }
                .frame(width: width, height: height)
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.snappy(duration: 0.18), value: isOn)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 && isEnabled }
            .accessibilityLabel(Text("Switch"))
            .accessibilityValue(Text(isOn ? "On" : "Off"))
        }
    }
}

extension ToggleStyle where Self == PanelSwitchStyle {
    static var panelSwitch: PanelSwitchStyle { PanelSwitchStyle() }
}

/// A flat segmented control: a quiet track with a sliding selection.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Namespace private var namespace
    @Environment(\.isEnabled) private var isEnabled

    init(selection: Binding<Value>, options: [(value: Value, label: String)]) {
        _selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Segment(label: option.label, isSelected: option.value == selection, namespace: namespace) {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                }
            }
        }
        .padding(2)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isEnabled ? 1 : 0.45)
    }

    private struct Segment: View {
        let label: String
        let isSelected: Bool
        let namespace: Namespace.ID
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : hovering ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.accent)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        } else if hovering {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.06))
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// The RouteBar mark from `logo.svg`: three arrows leaving one trunk.
///
/// Drawn as a stroked shape so it takes any colour and opacity.
struct RouteBarMark: Shape {
    func path(in rect: CGRect) -> Path {
        // The arrows span x 216…808 and y 174…850 on the logo's 1024-unit artboard.
        let side = 676.0
        let scale = min(rect.width, rect.height) / side
        let origin = CGPoint(x: rect.midX - side * scale / 2, y: rect.midY - side * scale / 2)
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + (x - (512 - side / 2)) * scale, y: origin.y + (y - (512 - side / 2)) * scale)
        }
        let center = 512.0, spread = 228.0, trunk = 258.0, bend = 372.0, settle = 556.0
        let sideTip = 708.0, middleTip = 766.0, head = 96.0 * 0.7071
        var path = Path()
        for y in [center - spread, center + spread] {
            path.move(to: point(trunk, center))
            path.addLine(to: point(bend, center))
            let mid = (bend + settle) / 2
            path.addCurve(to: point(settle, y), control1: point(mid, center), control2: point(mid, y))
            path.addLine(to: point(sideTip, y))
        }
        path.move(to: point(trunk, center))
        path.addLine(to: point(middleTip, center))
        for (tip, y) in [(sideTip, center - spread), (middleTip, center), (sideTip, center + spread)] {
            path.move(to: point(tip - head, y - head))
            path.addLine(to: point(tip, y))
            path.addLine(to: point(tip - head, y + head))
        }
        return path.strokedPath(StrokeStyle(lineWidth: 84 * scale, lineCap: .round, lineJoin: .round))
    }
}

/// "RouteBar 1.5.0" with the mark, faint enough to ignore and plain enough to
/// tell what the app is in a screenshot.
struct BrandMark: View {
    var opacity = 0.32

    static var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        HStack(spacing: 4) {
            RouteBarMark().frame(width: 10, height: 10)
            Text("RouteBar").font(.system(size: 10, weight: .semibold))
            if let version = Self.version {
                Text(version).font(.system(size: 9.5, weight: .medium, design: .rounded)).monospacedDigit()
            }
        }
        .foregroundStyle(.primary)
        .opacity(opacity)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
