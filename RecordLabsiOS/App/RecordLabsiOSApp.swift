import SwiftUI

@main
struct RecordLabsiOSApp: App {
    @StateObject private var playerConnection = PlayerConnection()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(playerConnection)
        }
    }
}
