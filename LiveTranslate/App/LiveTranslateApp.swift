import SwiftUI

@main
struct LiveTranslateApp: App {
    @StateObject private var translator = LiveTranslator.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(translator)
                .preferredColorScheme(.dark)
        }
    }
}
