import SwiftUI
import WidgetKit

@main
struct RescueReadyApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        .onChange(of: scenePhase) { _, phase in
            // Refresh the home screen widget with any pickups, handovers or discards.
            if phase == .background {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
