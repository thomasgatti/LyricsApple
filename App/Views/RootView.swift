import SwiftUI

struct RootView: View {
    @Environment(SpotifyAuthService.self) private var auth

    var body: some View {
        Group {
            if auth.isAuthorized {
                NowPlayingView()
                    .transition(.opacity)
            } else {
                ConnectView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: auth.isAuthorized)
    }
}
