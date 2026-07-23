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
            // Task 15 replaces this.
            PhoneColumn { Text(config.summary) }
        case .results:
            // Task 17 replaces this.
            PhoneColumn { Text("Results") }
        case .progress:
            // Task 18 replaces this.
            PhoneColumn { Text("Your tables") }
        }
    }
}
