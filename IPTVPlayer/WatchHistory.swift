import Foundation

/// Ein Eintrag im Verlauf: wie weit ein Film / eine Folge geschaut wurde
struct WatchEntry: Codable, Identifiable, Hashable {
    let id: String              // = Channel.id
    var name: String
    var group: String
    var logoURL: URL?
    var streamURL: URL
    var kind: Channel.Kind
    var position: Double        // Sekunden
    var duration: Double        // Sekunden
    var updatedAt: Date
    // Nur bei Serienfolgen
    var seriesID: Int?
    var seriesName: String?
    var seriesCover: URL?
    var season: Int?
    var episode: Int?

    var progress: Double { duration > 0 ? min(position / duration, 1) : 0 }
    var isFinished: Bool { progress >= 0.93 || (duration > 0 && duration - position < 120) }

    var remainingText: String {
        let minutes = Int(max(duration - position, 0) / 60)
        return minutes >= 60 ? "noch \(minutes / 60) Std. \(minutes % 60) Min." : "noch \(minutes) Min."
    }

    var episodeLabel: String {
        guard let season, let episode else { return name }
        return "S\(season) F\(episode) · \(name)"
    }

    var asChannel: Channel {
        Channel(id: id, name: name, group: group, logoURL: logoURL, streamURL: streamURL, kind: kind,
                seriesID: seriesID, seriesName: seriesName, seriesCover: seriesCover,
                season: season, episode: episode)
    }
}

/// Merkt sich, wo du bei Filmen und Folgen aufgehört hast
final class WatchHistory: ObservableObject {
    static let shared = WatchHistory()

    @Published private(set) var entries: [WatchEntry] = []

    private let file = URL.documentsDirectory.appending(path: "history.json")
    private let maxEntries = 300

    private init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([WatchEntry].self, from: data) {
            entries = saved
        }
    }

    func entry(for channel: Channel) -> WatchEntry? { entries.first { $0.id == channel.id } }

    /// Startpunkt beim erneuten Öffnen (nil = von vorn)
    func resumePosition(for channel: Channel) -> Double? {
        guard let e = entry(for: channel), !e.isFinished, e.position > 15 else { return nil }
        return e.position - 3   // ein paar Sekunden zurück, damit man wieder reinkommt
    }

    /// Angefangene Filme und Folgen
    var continueWatching: [WatchEntry] {
        entries.filter { $0.kind != .live && !$0.isFinished && $0.progress > 0.01 }
    }

    /// Je Serie die zuletzt geschaute Folge
    var currentSeries: [WatchEntry] {
        var seen = Set<Int>()
        return entries.filter { e in
            guard let id = e.seriesID else { return false }
            return seen.insert(id).inserted
        }
    }

    func update(channel: Channel, position: Double, duration: Double) {
        guard channel.kind != .live, duration > 0 else { return }
        var e = WatchEntry(id: channel.id, name: channel.name, group: channel.group,
                           logoURL: channel.logoURL, streamURL: channel.streamURL, kind: channel.kind,
                           position: position, duration: duration, updatedAt: Date(),
                           seriesID: channel.seriesID, seriesName: channel.seriesName,
                           seriesCover: channel.seriesCover, season: channel.season, episode: channel.episode)
        if let old = entry(for: channel), e.seriesID == nil {
            e.seriesID = old.seriesID; e.seriesName = old.seriesName
            e.seriesCover = old.seriesCover; e.season = old.season; e.episode = old.episode
        }
        entries.removeAll { $0.id == channel.id }
        entries.insert(e, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        save()
    }

    func remove(_ entry: WatchEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Ganze Serie aus „Meine Serien“ entfernen
    func removeSeries(_ seriesID: Int) {
        entries.removeAll { $0.seriesID == seriesID }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file) }
    }
}
