import SwiftUI

@main
struct MacDiskImagerApp: App {
    var body: some Scene {
        WindowGroup { ContentView().frame(minWidth: 760, minHeight: 540) }
        .windowResizability(.contentSize)
    }
}
