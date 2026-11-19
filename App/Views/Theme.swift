import SwiftUI

enum Theme {
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.38)
    static let accentSecondary = Color(red: 1.0, green: 0.37, blue: 0.47)
    static let backgroundTop = Color(red: 0.09, green: 0.08, blue: 0.19)
    static let backgroundBottom = Color(red: 0.27, green: 0.13, blue: 0.35)

    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let backgroundGradient = LinearGradient(
        colors: [backgroundTop, backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// Sfondo: copertina sfocata, oppure gradiente dell'app.
struct ArtworkBackground: View {
    let artworkURL: URL?

    var body: some View {
        ZStack {
            Theme.backgroundGradient
            if let artworkURL {
                AsyncImage(url: artworkURL) { image in
                    image.resizable().scaledToFill().blur(radius: 70).opacity(0.85)
                } placeholder: {
                    Color.clear
                }
                .transition(.opacity)
            }
            Color.black.opacity(0.45)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: artworkURL)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accentGradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Messaggio centrale con icona e azione opzionale (nessun testo, errore, ...).
struct MessageView: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusBanner: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
