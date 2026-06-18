import SwiftUI

@main
struct WispMobileApp: App {
    @StateObject private var model = DictationModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    model.handleURL(url)
                }
                .onAppear {
                    model.handlePendingKeyboardRequest()
                }
        }
    }
}
