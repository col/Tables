import SwiftUI
import SwiftData

@main
struct TablesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FactStat.self, GameRun.self])
    }
}

/// Placeholder shell. Task 13 replaces this with the real navigation stack.
struct RootView: View {
    var body: some View {
        Color(red: 0.949, green: 0.937, blue: 0.910)
            .ignoresSafeArea()
    }
}
