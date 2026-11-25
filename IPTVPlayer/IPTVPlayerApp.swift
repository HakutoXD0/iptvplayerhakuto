import SwiftUI
import AVFoundation

@main
struct IPTVPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PlaylistStore()
    @StateObject private var downloads = DownloadManager.shared

    init() {
        // Ton auch bei Lautlos-Schalter + Voraussetzung für Bild-in-Bild
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(downloads)
        }
    }
}
