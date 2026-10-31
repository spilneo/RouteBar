import RouteBarKit
import SwiftUI

/// The whole menu bar panel, top to bottom: status, endpoint, usage,
/// providers with their limits, model search, and the footer toolbar.
struct PanelView: View {
    @Bindable var model: AppModel

    var body: some View {
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
        .padding(12)
        .frame(width: Theme.width)
        .tint(Theme.accent)
        .onAppear { model.isPanelVisible = true }
        .onDisappear { model.isPanelVisible = false }
        .animation(.snappy(duration: 0.25), value: model.notice)
        .animation(.snappy(duration: 0.25), value: model.tiles)
    }
}
