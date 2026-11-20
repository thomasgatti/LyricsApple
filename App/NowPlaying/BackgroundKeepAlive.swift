import AVFoundation
import Foundation

/// Mantiene Lyrics attiva quando l'iPhone è bloccato o l'app è in background, così Live Activity
/// e widget (schermata di blocco e CarPlay) continuano a seguire il testo.
///
/// Come funziona: riproduce in loop un file di silenzio con una sessione audio "mixWithOthers",
/// che si somma a Spotify senza interromperlo né sostituirlo nei controlli "In riproduzione".
/// Usa `AVAudioPlayer` (più robusto di `AVAudioEngine`, che si ferma da solo quando cambia
/// l'uscita audio, per esempio collegando CarPlay) e si riavvia dopo interruzioni e cambi di uscita.
/// Richiede `UIBackgroundModes = audio` in Info.plist.
/// Nota: è adatto a un'app personale; l'App Store non accetterebbe questo uso dell'audio in background.
@MainActor
final class BackgroundKeepAlive {
    private var player: AVAudioPlayer?
    private var wantsToRun = false
    private var observers: [NSObjectProtocol] = []

    /// Quante volte è stato necessario riavviarlo (per la diagnostica nelle Impostazioni).
    private(set) var restartCount = 0

    var isRunning: Bool { player?.isPlaying == true }

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            AVAudioSession.interruptionNotification,
            AVAudioSession.routeChangeNotification,
            AVAudioSession.mediaServicesWereResetNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let isInterruptionBegin = notification.name == AVAudioSession.interruptionNotification
                    && (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                        == AVAudioSession.InterruptionType.began.rawValue
                let rebuild = notification.name == AVAudioSession.mediaServicesWereResetNotification
                MainActor.assumeIsolated {
                    guard let self, self.wantsToRun, !isInterruptionBegin else { return }
                    // Fine telefonata/Siri, CarPlay collegato o scollegato, servizi audio riavviati: ripartiamo.
                    if rebuild { self.player = nil }
                    self.ensureRunning()
                }
            })
        }
    }

    func start() {
        wantsToRun = true
        ensureRunning()
    }

    /// Da chiamare spesso (a ogni controllo su Spotify): se il silenzio si è fermato, lo fa ripartire.
    func ensureRunning() {
        guard wantsToRun, !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if player == nil {
                let player = try AVAudioPlayer(data: Self.silentWAV)
                player.numberOfLoops = -1
                player.prepareToPlay()
                self.player = player
            } else {
                restartCount += 1
            }
            player?.play()
        } catch {
            player = nil
        }
    }

    func stop() {
        wantsToRun = false
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Un secondo di silenzio (WAV PCM 16 bit, mono, 8 kHz) creato in memoria.
    nonisolated static let silentWAV: Data = {
        let sampleRate: UInt32 = 8_000
        let samples = sampleRate // 1 secondo
        let dataSize = samples * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))            // PCM, mono
        append(sampleRate); append(sampleRate * 2)      // frequenza, byte al secondo
        append(UInt16(2)); append(UInt16(16))           // byte per campione, bit
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }()
}
