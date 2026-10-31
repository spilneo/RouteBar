import Charts
import RouteBarKit
import SwiftUI

/// Daily token traffic with a headline figure. Hovering a bar shows that day.
struct UsageCard: View {
    @Bindable var model: AppModel
    @State private var selectedDate: Date?

    private static let gradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.36, blue: 1), Color(red: 0.13, green: 0.76, blue: 1)],
        startPoint: .top, endPoint: .bottom
    )

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
        Card {
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
                    Picker("Range", selection: $model.range) {
                        ForEach(UsageRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 84)
                }
                chart
            }
        }
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
            .foregroundStyle(hasTraffic ? AnyShapeStyle(Self.gradient) : AnyShapeStyle(.primary.opacity(0.07)))
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
        .frame(height: 64)
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
