import RouteBarKit
import SwiftUI

/// Status, live traffic and OmniRoute's version on the left, the dashboard and
/// the endpoint switch on the right.
struct HeaderView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: model.server, isBusy: model.activeRequests > 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.numericText())
                subtitle
            }
            Spacer(minLength: 4)
            IconButton(systemImage: "arrow.up.forward.app", help: "Open the OmniRoute dashboard") {
                model.open(model.dashboardURL)
            }
            .disabled(model.server != .running)
            Toggle("Endpoint", isOn: Binding(get: { model.server.isOn }, set: { model.setServer(on: $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(model.server == .stopping)
                .help(toggleHelp)
        }
        .padding(.horizontal, 4)
    }

    private var title: String {
        switch model.server {
        case .running: model.activeRequests > 0 ? "Serving \(model.activeRequests)" : "Running"
        case .starting: "Starting…"
        case .stopping: "Stopping…"
        case .stopped: model.isRemote ? "Not reachable" : "Off"
        }
    }

    private var toggleHelp: String {
        if model.isRemote {
            return model.server.isOn ? "Stop OmniRoute on \(model.serverLabel)" : "Start OmniRoute on \(model.serverLabel) to connect"
        }
        return model.server.isOn ? "Turn the endpoint off" : "Turn the endpoint on"
    }

    private var serverName: String {
        model.isRemote ? "OmniRoute on \(model.serverLabel)" : "OmniRoute"
    }

    @ViewBuilder private var subtitle: some View {
        if let version = model.version, version.updateAvailable == true, let latest = version.latest {
            Button {
                model.open(model.dashboardURL)
            } label: {
                Text("OmniRoute \(latest) is available")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .help("Update from the OmniRoute dashboard")
        } else {
            Text(model.version?.current.map { "\(serverName) \($0)" } ?? serverName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Green when running, amber while changing state, grey when off. Pulses while
/// requests are in flight.
struct StatusDot: View {
    let state: ServerState
    let isBusy: Bool

    private var color: Color {
        switch state {
        case .running: .green
        case .starting, .stopping: .orange
        case .stopped: .secondary
        }
    }

    private var pulses: Bool { isBusy || state == .starting || state == .stopping }

    var body: some View {
        ZStack {
            if pulses {
                Circle().fill(color.opacity(0.25)).frame(width: 18, height: 18)
                    .phaseAnimator([0.6, 1.25]) { halo, scale in
                        halo.scaleEffect(scale).opacity(1.4 - Double(scale))
                    } animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                Circle().fill(color.opacity(0.18)).frame(width: 18, height: 18)
            }
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
