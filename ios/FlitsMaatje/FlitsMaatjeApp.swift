import SwiftUI

@main
struct FlitsMaatjeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        BootLogger.mark("swiftui-app-init")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
