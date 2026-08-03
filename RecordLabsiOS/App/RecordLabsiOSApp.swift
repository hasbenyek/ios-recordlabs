import SwiftUI

@main
struct RecordLabsiOSApp: App {
    // A real launch storyboard is required so iOS uses the native full-screen
    // scene on modern iPhones instead of treating the app as legacy-sized.
    @StateObject private var playerConnection = PlayerConnection()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(playerConnection)
        }
    }
}
