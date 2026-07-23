import SwiftUI
import SwiftData

@main
struct TablesApp: App {
    @State private var router = AppRouter()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(settings)
                .tint(Color.skyText)
        }
        .modelContainer(for: [FactStat.self, GameRun.self])
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            HomeView()
                .navigationBarBackButtonHidden()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                        .navigationBarBackButtonHidden()
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
        .background(Color.canvas)
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .setup(let mode):
            SetupView(mode: mode)
        case .game(let config):
            GameView(config: config)
        case .results:
            if let summary = router.summary {
                ResultsView(summary: summary)
            } else {
                // Only reachable if the stack is restored without a summary.
                PhoneColumn { Color.canvas }
                    .onAppear { router.goHome() }
            }
        case .progress:
            // Task 18 replaces this.
            PhoneColumn { Text("Your tables") }
        }
    }
}
