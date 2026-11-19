import Foundation

/// Parser del formato LRC: "[mm:ss.xx] testo".
/// Supporta più timestamp per riga, millisecondi a 2 o 3 cifre, il tag [offset:±ms] e ignora i metadati ([ar:], [ti:], ...).
enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [(time: TimeInterval, text: String)] = []
        var offsetSeconds: TimeInterval = 0

        for rawLine in lrc.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseTimestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:") {
                    let value = tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)
                    offsetSeconds = (Double(value) ?? 0) / 1000
                }
                rest = rest[rest.index(after: close)...]
            }

            guard !times.isEmpty else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                entries.append((time, text))
            }
        }

        // Ordinamento stabile per tempo; l'offset LRC positivo anticipa il testo.
        let sorted = entries.enumerated().sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }
        return sorted.enumerated().map { index, entry in
            LyricLine(id: index, time: max(0, entry.element.time - offsetSeconds), text: entry.element.text)
        }
    }

    /// "mm:ss", "mm:ss.xx", "mm:ss.xxx", "mm:ss:xx".
    static func parseTimestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Int(parts[0].trimmingCharacters(in: .whitespaces)), minutes >= 0
        else { return nil }

        if parts.count == 2 {
            let secondsText = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            guard let seconds = Double(secondsText), seconds >= 0, seconds < 60 else { return nil }
            return TimeInterval(minutes * 60) + seconds
        } else {
            guard let seconds = Int(parts[1]), let centis = Int(parts[2]), seconds < 60 else { return nil }
            return TimeInterval(minutes * 60 + seconds) + TimeInterval(centis) / 100
        }
    }
}
