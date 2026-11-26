import Foundation

nonisolated struct Channel: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable, Hashable { case live, movie, episode }

    let id: String
    let name: String
    let group: String
    let logoURL: URL?
    let streamURL: URL
    var kind: Kind = .live
    var xtreamStreamID: Int? = nil
    // Nur bei Serienfolgen (für den Verlauf)
    var seriesID: Int? = nil
    var seriesName: String? = nil
    var seriesCover: URL? = nil
    var season: Int? = nil
    var episode: Int? = nil
    // Für Sortierung und Zufalls-Vorschlag
    var addedAt: Date? = nil
    var year: Int? = nil
    var rating: Double? = nil

    /// Xtream: stabile ID, M3U: Stream-URL – bleibt beim Neuladen gleich
    var favoriteKey: String { xtreamStreamID != nil ? id : streamURL.absoluteString }
}

/// Liste + Gruppen in sinnvoller Reihenfolge
nonisolated struct ChannelCollection: Sendable {
    var channels: [Channel] = []
    var groups: [String] = []

    init() {}

    init(_ channels: [Channel], groupOrder: [String]? = nil) {
        self.channels = channels
        let used = Set(channels.map(\.group))
        if let groupOrder {
            var seen = Set<String>()
            groups = groupOrder.filter { used.contains($0) && seen.insert($0).inserted }
            for g in channels.map(\.group) where seen.insert(g).inserted { groups.append(g) }
        } else {
            var seen = Set<String>()
            groups = channels.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
        }
    }
}

/// Liest M3U / M3U8-Playlists (#EXTINF mit tvg-logo, group-title usw.)
nonisolated enum M3UParser {

    static func parse(_ text: String) -> [Channel] {
        var result: [Channel] = []
        var name: String?
        var attrs: [String: String] = [:]
        var extGroup: String?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF") {
                (name, attrs) = parseExtInf(line)
            } else if line.hasPrefix("#EXTGRP:") {
                extGroup = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#") {
                continue
            } else if let url = makeURL(line) {
                let group = nonEmpty(attrs["group-title"]) ?? extGroup ?? "Sonstige"
                let title = nonEmpty(name) ?? nonEmpty(attrs["tvg-name"]) ?? url.lastPathComponent
                result.append(Channel(
                    id: "m3u-\(result.count)",
                    name: title,
                    group: group,
                    logoURL: nonEmpty(attrs["tvg-logo"]).flatMap(URL.init(string:)),
                    streamURL: url
                ))
                name = nil
                attrs = [:]
                extGroup = nil
            }
        }
        return result
    }

    /// `#EXTINF:-1 tvg-id="x" tvg-logo="y" group-title="Sport",Sendername`
    private static func parseExtInf(_ line: String) -> (String, [String: String]) {
        let chars = Array(line)

        // Name = alles nach dem ersten Komma außerhalb von Anführungszeichen
        var inQuotes = false
        var commaIndex: Int?
        for (i, c) in chars.enumerated() {
            if c == "\"" { inQuotes.toggle() }
            else if c == "," && !inQuotes { commaIndex = i; break }
        }
        let head = commaIndex.map { String(chars[..<$0]) } ?? line
        let name = commaIndex.map { String(chars[($0 + 1)...]).trimmingCharacters(in: .whitespaces) } ?? ""

        // Attribute key="value"
        var attrs: [String: String] = [:]
        var rest = Substring(head)
        while let eq = rest.range(of: "=\"") {
            let key = rest[..<eq.lowerBound].split(separator: " ").last.map(String.init) ?? ""
            let valuePart = rest[eq.upperBound...]
            guard let endQuote = valuePart.firstIndex(of: "\"") else { break }
            attrs[key.lowercased()] = String(valuePart[..<endQuote])
            rest = valuePart[valuePart.index(after: endQuote)...]
        }
        return (name, attrs)
    }

    private static func makeURL(_ s: String) -> URL? {
        if let url = URL(string: s), url.scheme != nil { return url }
        if let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded), url.scheme != nil { return url }
        return nil
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
