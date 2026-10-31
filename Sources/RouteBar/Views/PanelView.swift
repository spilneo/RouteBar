import RouteBarKit
import SwiftUI

/// The whole menu bar panel, top to bottom: status, endpoint, usage,
/// providers with their limits, model search, and the footer toolbar.
/// The gear swaps it for the Settings screen in place.
struct PanelView: View {
    @Bindable var model: AppModel
    private var appearance = Appearance.shared

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        Group {
            if model.showsSettings {
                SettingsView(model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                dashboard
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(width: Theme.width)
        .background {
            if !appearance.isTranslucent {
                Color(nsColor: .windowBackgroundColor).padding(-40)
            }
        }
        .tint(Theme.accent)
        .onAppear { model.isPanelVisible = true }
        .onDisappear {
            model.isPanelVisible = false
            model.showsSettings = false
        }
        .animation(.snappy(duration: 0.25), value: model.notice)
        .animation(.snappy(duration: 0.25), value: model.tiles)
        .animation(.snappy(duration: 0.2), value: appearance.accent)
    }

    private var dashboard: some View {
        VStack(spacing: 10) {
            HeaderView(model: model)
            EndpointField(model: model)
            UsageView(model: model)
            ProvidersView(model: model)
            ModelSearchView(model: model)
            if let message = model.notice ?? model.problem {
                NoticeBar(message: message, isProblem: model.notice == nil)
            }
            FooterBar(model: model)
        }
    }
}
