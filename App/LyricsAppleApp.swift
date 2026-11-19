import SwiftUI

@main
struct LyricsAppleApp: App {
    @State private var auth: SpotifyAuthService
    @State private var nowPlaying: NowPlayingViewModel
    @State private var network = NetworkMonitor()

    init() {
        let auth = SpotifyAuthService()
        _auth = State(initialValue: auth)
        _nowPlaying = State(initialValue: NowPlayingViewModel(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(nowPlaying)
                .environment(network)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in auth.handleOpenURL(url) }
        }
    }
}
