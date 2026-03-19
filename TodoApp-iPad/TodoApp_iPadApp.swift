import SwiftUI
import Firebase
import GoogleSignIn

@main
struct TodoApp_iPadApp: App {

    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        PersistenceManager.shared.migrateToAppGroupIfNeeded()
        NotificationManager.shared.requestPermission()

        // Set the correct backend and start listeners if already signed in
        let auth = AuthenticationManager.shared
        if auth.isSignedIn {
            SyncManager.shared.setBackend(for: auth.authProvider)
            SyncManager.shared.startListening()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                let auth = AuthenticationManager.shared
                if auth.isSignedIn {
                    SyncManager.shared.setBackend(for: auth.authProvider)
                    SyncManager.shared.startListening()
                }
            }
        }
    }
}
