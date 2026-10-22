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

            BatchListView(
                viewModel: container.makeBatchListViewModel(),
                makeHandoverViewModel: container.makeHandoverViewModel,
                makeSafetyCheckViewModel: container.makeSafetyCheckViewModel
            )
            .tabItem {
                Label("Batches", systemImage: "tray.full")
            }
                .tabItem { Label("Batches", systemImage: "tray.full") }

            PickupLogView(viewModel: container.makePickupViewModel())
                .tabItem { Label("Log Pickup", systemImage: "plus.circle") }

            UpcomingFeatureView(
                title: "Impact",
                systemImage: "chart.bar",
                message: "Food saved and meals delivered will appear here."
            )
            .tabItem { Label("Impact", systemImage: "chart.bar") }
        }
    }
}

/// Temporary tab content until the feature's own screen is merged.
private struct UpcomingFeatureView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .navigationTitle(title)
        }
    }
}

#Preview {
    RootView(container: .preview())
}
