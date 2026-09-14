import SwiftUI

/// The container app exists mostly so the Messages extension has somewhere to
/// live, and so you have somewhere to paste the API key. All the real work
/// happens in the extension.
@main
struct EnDraftApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SettingsView()
            }
        }
    }
}
