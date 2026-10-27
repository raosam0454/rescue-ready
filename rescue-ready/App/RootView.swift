import SwiftUI

/// Prepares the data store, then shows the main tabs.
struct RootView: View {
    let container: AppContainer
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                tabs
            } else {
                ProgressView("Getting things ready")
            }
        }
        .task {
            await container.prepare()
            isReady = true
        }
    }

    private var tabs: some View {
        TabView {
            BatchListView(viewModel: container.makeBatchListViewModel(),
                          makeSafetyCheckViewModel: container.makeSafetyCheckViewModel,
                          makeHandoverViewModel: container.makeHandoverViewModel)
                .tabItem { Label("Batches", systemImage: "tray.full") }

            PickupLogView(viewModel: container.makePickupViewModel())
                .tabItem { Label("Log Pickup", systemImage: "plus.circle") }

            ImpactDashboardView(viewModel: container.makeImpactViewModel())
                .tabItem { Label("Impact", systemImage: "chart.bar") }
        }
    }
}

#Preview {
    RootView(container: .preview())
}
