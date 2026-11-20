import SwiftUI
import WidgetKit
import XCTest
@testable import LyricsApple

/// Disegna le anteprime di widget e Live Activity (formati CarPlay, schermata di blocco, Home)
/// e le salva come PNG. Su GitHub finiscono nel file scaricabile "anteprime".
/// Cartella: variabile PREVIEW_DIR (impostata dalla build), altrimenti una cartella temporanea.
@MainActor
final class PreviewRenderTests: XCTestCase {
    private let now = Date()

    private var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["PREVIEW_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("anteprime", isDirectory: true)
    }

    // MARK: Dati di prova (testo inventato)

    private func activityState(current: String, playing: Bool = true) -> LyricsActivityAttributes.ContentState {
        .init(
            title: "Canzone di prova",
            artist: "Artista di prova",
            currentLine: current,
            nextLine: "e la riga che arriva subito dopo",
            isPlaying: playing,
            hasLyrics: true,
            previousLine: "la riga che è appena finita",
            afterNextLine: "poi ancora un'altra riga",
            lineIndex: 4,
            lineStart: now.addingTimeInterval(-1.5),
            lineEnd: now.addingTimeInterval(2.5),
            songStart: now.addingTimeInterval(-70),
            songEnd: now.addingTimeInterval(110)
        )
    }

    private var widgetSnapshot: LyricsWidgetSnapshot {
        LyricsWidgetSnapshot(
            trackID: "demo",
            title: "Canzone di prova",
            artist: "Artista di prova",
            isPlaying: true,
            statusLine: nil,
            lines: [
                .init(start: now.addingTimeInterval(-4), text: "la riga che è appena finita"),
                .init(start: now.addingTimeInterval(-1), text: "Questa è la riga che stai ascoltando adesso"),
                .init(start: now.addingTimeInterval(3), text: "e la riga che arriva subito dopo"),
                .init(start: now.addingTimeInterval(6), text: "poi ancora un'altra riga"),
            ],
            songEnd: now.addingTimeInterval(110)
        )
    }

    private func widgetEntry(_ content: LyricsEntry.Content) -> LyricsEntry {
        LyricsEntry(date: now, content: content)
    }

    // MARK: Anteprime

    func testRenderPreviews() throws {
        let long = "Questa è la riga che stai ascoltando adesso"
        let short = "Riga breve"
        let lineEntry = widgetEntry(.line(widgetSnapshot, index: 1))

        let sheet = VStack(alignment: .leading, spacing: 22) {
            Text("Anteprime Lyrics").font(.title.bold()).foregroundStyle(.white)

            section("CarPlay · widget piccolo (circa 170×170)") {
                HStack(spacing: 16) {
                    widgetTile(lineEntry, family: .systemSmall, size: CGSize(width: 170, height: 170))
                    widgetTile(widgetEntry(.status(widgetSnapshot, "Testo non disponibile")), family: .systemSmall, size: CGSize(width: 170, height: 170))
                    widgetTile(widgetEntry(.nothing), family: .systemSmall, size: CGSize(width: 170, height: 170))
                }
            }

            section("CarPlay · Live Activity piccola (dimensione indicativa)") {
                HStack(spacing: 16) {
                    activityTile(SmallLyricsView(state: activityState(current: long)), size: CGSize(width: 170, height: 170))
                    activityTile(SmallLyricsView(state: activityState(current: short)), size: CGSize(width: 180, height: 90))
                    activityTile(SmallLyricsView(state: activityState(current: long, playing: false)), size: CGSize(width: 180, height: 90))
                }
            }

            section("CarPlay · riquadro accanto alla mappa (formato visto sulla C3)") {
                HStack(spacing: 16) {
                    activityTile(SmallLyricsView(state: activityState(current: long)), size: CGSize(width: 250, height: 80))
                    activityTile(SmallLyricsView(state: activityState(current: "Fra, la mia tipa mi ha portato a cena perché aveva fame")), size: CGSize(width: 250, height: 80))
                }
            }

            section("Schermata di blocco · Live Activity  (sotto: quando Lyrics è stata sospesa)") {
                VStack(spacing: 10) {
                    activityTile(LockScreenLyricsView(state: activityState(current: long)), size: CGSize(width: 370, height: 160))
                    activityTile(LockScreenLyricsView(state: activityState(current: long).staleVersion()), size: CGSize(width: 370, height: 160))
                }
            }

            section("Home · widget medio  ·  Schermata di blocco · widget sotto l'orologio") {
                HStack(alignment: .top, spacing: 16) {
                    widgetTile(lineEntry, family: .systemMedium, size: CGSize(width: 338, height: 158))
                    AccessoryLyricsView(entry: lineEntry)
                        .foregroundStyle(.white)
                        .frame(width: 172, height: 76)
                        .padding(6)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(28)
        .frame(width: 640, alignment: .leading)
        .background(Color(white: 0.07))
        .environment(\.colorScheme, .dark)

        try save(sheet, named: "anteprime.png")
    }

    func testRenderFloatingWindowFrame() throws {
        let texts = CarModeTexts(title: "Canzone di prova · Artista di prova",
                                 current: "Questa è la riga che stai ascoltando adesso",
                                 next: "e la riga che arriva subito dopo")
        XCTAssertNotNil(FloatingLyricsController.makeSampleBuffer(texts: texts), "Il fotogramma video deve crearsi")
        let image = UIGraphicsImageRenderer(size: FloatingLyricsController.frameSize).image { _ in
            FloatingLyricsController.drawFrame(texts: texts, size: FloatingLyricsController.frameSize)
        }
        let data = try XCTUnwrap(image.pngData())
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try data.write(to: outputDirectory.appendingPathComponent("finestra-flottante.png"))
    }

    func testRenderCarModePreview() throws {
        let model = NowPlayingViewModel(auth: SpotifyAuthService())
        let screen = CarModeContent(
            texts: CarModeTexts(title: "Canzone di prova · Artista di prova",
                                current: "Questa è la riga che stai ascoltando adesso",
                                next: "e la riga che arriva subito dopo"),
            dimScreen: .constant(true),
            onClose: {}
        )
        .environment(model)
        .frame(width: 390, height: 844)
        .environment(\.colorScheme, .dark)
        try save(screen, named: "modalita-auto.png")
    }

    // MARK: Aiuti

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            content()
        }
    }

    private func widgetTile(_ entry: LyricsEntry, family: WidgetFamily, size: CGSize) -> some View {
        LyricsWidgetContent(entry: entry, family: family)
            .padding(14)
            .frame(width: size.width, height: size.height)
            .background(LyricsWidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func activityTile(_ view: some View, size: CGSize) -> some View {
        view
            .frame(width: size.width, height: size.height)
            .background(LyricsPalette.background.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func save(_ view: some View, named name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "Impossibile disegnare \(name)")
        let data = try XCTUnwrap(image.pngData())
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appendingPathComponent(name)
        try data.write(to: url)
        print("Anteprima salvata: \(url.path)")
    }
}
