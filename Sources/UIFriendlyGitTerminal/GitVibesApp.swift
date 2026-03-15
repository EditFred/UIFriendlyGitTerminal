import SwiftUI

@main
struct GitVibesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(nil)
        }
        .windowResizability(.contentSize)
    }
}
