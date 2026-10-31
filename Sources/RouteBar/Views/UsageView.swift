import Charts
import RouteBarKit
import SwiftUI

/// Daily token traffic with a headline figure. Hovering a bar shows that day.
struct UsageView: View {
    @Bindable var model: AppModel
    @State private var selectedDate: Date?

    private var selected: UsagePoint? {
        guard let selectedDate else { return nil }
        return model.usage.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var totals: (tokens: Int, requests: Int) {
        if let selected { return (selected.tokens, selected.requests) }
        return (model.usage.reduce(0) { $0 + $1.tokens }, model.usage.reduce(0) { $0 + $1.requests })
    }

    private var hasTraffic: Bool { model.usage.contains { $0.tokens > 0 || $0.requests > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Dashboard.compact(totals.tokens))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("tokens")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                RangeSwitch(selection: $model.range)
            }
            chart
        }
        .surface()
    }

    private var detail: String {
        if let selected {
            return "\(selected.requests) requests on \(selected.date.formatted(.dateTime.weekday(.wide).day().month()))"
        }
        var parts = ["\(Dashboard.compact(totals.requests)) requests"]
        if let rate = model.summary?.successRatePct, totals.requests > 0 { parts.append("\(Int(rate.rounded()))% ok") }
        if let latency = model.summary?.avgLatencyMs, latency > 0 {
            parts.append(latency >= 1_000 ? String(format: "%.1fs avg", latency / 1_000) : "\(Int(latency))ms avg")
        }
        return parts.joined(separator: " · ")
    }

    private var chart: some View {
        Chart(model.usage) { point in
            BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Tokens", hasTraffic ? point.tokens : 1)
            )
            .foregroundStyle(hasTraffic ? Theme.accent : Color.primary.opacity(0.07))
            .opacity(selected == nil || selected?.date == point.date ? 1 : 0.35)
            .clipShape(RoundedRectangle(cornerRadius: model.usage.count > 10 ? 2 : 4, style: .continuous))
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: model.usage.count > 10 ? 7 : 1)) { _ in
                AxisValueLabel(format: model.usage.count > 10 ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.narrow))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 56)
        .overlay {
            if !hasTraffic {
                Text(model.server == .running ? "No traffic yet" : "Endpoint is off")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .offset(y: -8)
            }
        }
        .animation(.snappy, value: model.usage)
    }
}

/// Two-option switch: the chosen range sits on a soft pill, the other stays quiet.
struct RangeSwitch: View {
    @Binding var selection: UsageRange
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsageRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = range }
                } label: {
                    Text(range.label)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == range ? Color.primary : Color.secondary)
                        .frame(width: 34, height: 20)
                        .background {
                            if selection == range {
                                Capsule().fill(.primary.opacity(0.1)).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(range == .week ? "Last 7 days" : "Last 30 days")
            }
        }
        .padding(2)
        .background(.primary.opacity(0.04), in: Capsule())
    }
}
