import Foundation

// MARK: - Zugangsdaten

nonisolated struct XtreamAccount: Codable, Hashable, Sendable {
    var server: String
    var username: String
    var password: String

    /// "example.com:8080/" → "http://example.com:8080"
    var normalizedServer: String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

nonisolated enum XtreamError: LocalizedError {
    case invalidServer, authFailed, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidServer: "Die Server-Adresse ist ungültig."
        case .authFailed: "Anmeldung fehlgeschlagen – Benutzername, Passwort oder Server prüfen."
        case .http(let code): "Der Server hat mit Fehler \(code) geantwortet."
        }
    }
}

// MARK: - API-Modelle (Xtream liefert IDs mal als Zahl, mal als Text)

nonisolated struct XtreamUserInfo: Decodable, Sendable {
    let auth: Int
    let status: String?
    let expDate: Date?
    let maxConnections: String?

    enum CodingKeys: String, CodingKey {
        case auth, status, expDate = "exp_date", maxConnections = "max_connections"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        auth = c.flexInt(.auth) ?? 0
        status = c.flexString(.status)
        expDate = c.flexString(.expDate).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        maxConnections = c.flexString(.maxConnections)
    }
}

nonisolated struct XtreamAuthResponse: Decodable, Sendable {
    let userInfo: XtreamUserInfo?
    enum CodingKeys: String, CodingKey { case userInfo = "user_info" }
}

nonisolated struct XtreamCategory: Decodable, Sendable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey { case id = "category_id", name = "category_name" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexString(.id) ?? ""
        name = c.flexString(.name) ?? "Ohne Kategorie"
    }
}

nonisolated struct XtreamStream: Decodable, Sendable {
    let streamID: Int
    let name: String
    let icon: String?
    let categoryID: String?
    let containerExtension: String?
    let added: Date?
    let year: Int?
    let rating: Double?

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id", name, icon = "stream_icon",
             categoryID = "category_id", containerExtension = "container_extension",
             added, year, rating, releaseDate = "releasedate"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamID = c.flexInt(.streamID) ?? -1
        name = c.flexString(.name) ?? "Unbenannt"
        icon = c.flexString(.icon)
        categoryID = c.flexString(.categoryID)
        containerExtension = c.flexString(.containerExtension)
        added = c.flexString(.added).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        year = c.flexInt(.year) ?? YearParser.year(in: c.flexString(.releaseDate) ?? "") ?? YearParser.year(in: name)
        rating = c.flexDouble(.rating)
    }
}

nonisolated struct XtreamSeries: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let cover: String?
    let categoryID: String?
    let plot: String?
    let lastModified: Date?
    let year: Int?
    let rating: Double?
    var group = ""

    enum CodingKeys: String, CodingKey {
        case id = "series_id", name, cover, categoryID = "category_id", plot,
             lastModified = "last_modified", year, releaseDate, rating
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? -1
        name = c.flexString(.name) ?? "Unbenannt"
        cover = c.flexString(.cover)
        categoryID = c.flexString(.categoryID)
        plot = c.flexString(.plot)
        lastModified = c.flexString(.lastModified).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        year = c.flexInt(.year) ?? YearParser.year(in: c.flexString(.releaseDate) ?? "") ?? YearParser.year(in: name)
        rating = c.flexDouble(.rating)
    }
}

nonisolated struct XtreamEpisode: Decodable, Sendable, Identifiable {
    let id: String
    let episodeNum: Int
    let title: String
    let containerExtension: String

    enum CodingKeys: String, CodingKey {
        case id, episodeNum = "episode_num", title, containerExtension = "container_extension"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexString(.id) ?? UUID().uuidString
        episodeNum = c.flexInt(.episodeNum) ?? 0
        title = c.flexString(.title) ?? "Folge"
        containerExtension = c.flexString(.containerExtension) ?? "mp4"
    }
}

nonisolated struct XtreamSeason: Sendable, Identifiable {
    let season: Int
    let episodes: [XtreamEpisode]
    var id: Int { season }
}

nonisolated struct XtreamSeriesInfo: Decodable, Sendable {
    let seasons: [XtreamSeason]

    enum CodingKeys: String, CodingKey { case episodes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let dict = try? c.decode([String: [XtreamEpisode]].self, forKey: .episodes) {
            seasons = dict.map { XtreamSeason(season: Int($0.key) ?? 0, episodes: $0.value) }
                .sorted { $0.season < $1.season }
        } else if let arr = try? c.decode([[XtreamEpisode]].self, forKey: .episodes) {
            seasons = arr.enumerated().map { XtreamSeason(season: $0.offset + 1, episodes: $0.element) }
        } else {
            seasons = []
        }
    }
}

nonisolated struct XtreamEPGEntry: Decodable, Sendable, Identifiable {
    let title: String
    let description: String
    let start: Date?
    let end: Date?
    var id: String { "\(start?.timeIntervalSince1970 ?? 0)-\(title)" }

    enum CodingKeys: String, CodingKey {
        case title, description, start = "start_timestamp", end = "stop_timestamp"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = Self.base64(c.flexString(.title) ?? "")
        description = Self.base64(c.flexString(.description) ?? "")
        start = c.flexString(.start).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        end = c.flexString(.end).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    /// Xtream liefert EPG-Texte Base64-kodiert
    private static func base64(_ s: String) -> String {
        Data(base64Encoded: s).flatMap { String(data: $0, encoding: .utf8) } ?? s
    }
}

nonisolated struct XtreamEPGResponse: Decodable, Sendable {
    let listings: [XtreamEPGEntry]
    enum CodingKeys: String, CodingKey { case listings = "epg_listings" }
}

// MARK: - Client

nonisolated struct XtreamClient: Sendable {
    let account: XtreamAccount
    private var base: String { account.normalizedServer }

    func authenticate() async throws -> XtreamUserInfo {
        let response = try await get(XtreamAuthResponse.self, action: nil)
        guard let info = response.userInfo, info.auth == 1 else { throw XtreamError.authFailed }
        return info
    }

    func liveCategories() async throws -> [XtreamCategory] { try await get([XtreamCategory].self, action: "get_live_categories") }
    func liveStreams() async throws -> [XtreamStream] { try await get([XtreamStream].self, action: "get_live_streams") }
    func vodCategories() async throws -> [XtreamCategory] { try await get([XtreamCategory].self, action: "get_vod_categories") }
    func vodStreams() async throws -> [XtreamStream] { try await get([XtreamStream].self, action: "get_vod_streams") }
    func seriesCategories() async throws -> [XtreamCategory] { try await get([XtreamCategory].self, action: "get_series_categories") }
    func series() async throws -> [XtreamSeries] { try await get([XtreamSeries].self, action: "get_series") }

    func seriesInfo(id: Int) async throws -> XtreamSeriesInfo {
        try await get(XtreamSeriesInfo.self, action: "get_series_info", extra: [.init(name: "series_id", value: String(id))])
    }

    func shortEPG(streamID: Int) async throws -> [XtreamEPGEntry] {
        try await get(XtreamEPGResponse.self, action: "get_short_epg",
                      extra: [.init(name: "stream_id", value: String(streamID)), .init(name: "limit", value: "5")]).listings
    }

    // Stream-URLs (Live als HLS/.m3u8, das kann der iOS-Player direkt)
    func liveURL(_ id: Int) -> URL? { URL(string: "\(base)/live/\(enc(account.username))/\(enc(account.password))/\(id).m3u8") }
    func movieURL(_ id: Int, ext: String?) -> URL? { URL(string: "\(base)/movie/\(enc(account.username))/\(enc(account.password))/\(id).\(ext ?? "mp4")") }
    func episodeURL(_ id: String, ext: String) -> URL? { URL(string: "\(base)/series/\(enc(account.username))/\(enc(account.password))/\(id).\(ext)") }

    // Umwandeln in App-Modelle
    func collection(streams: [XtreamStream], categories: [XtreamCategory], kind: Channel.Kind) -> ChannelCollection {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let channels: [Channel] = streams.compactMap { s in
            let url = kind == .live ? liveURL(s.streamID) : movieURL(s.streamID, ext: s.containerExtension)
            guard let url else { return nil }
            return Channel(
                id: "\(kind.rawValue)-\(s.streamID)",
                name: s.name,
                group: names[s.categoryID ?? ""] ?? "Sonstige",
                logoURL: s.icon.flatMap(URL.init(string:)),
                streamURL: url,
                kind: kind,
                xtreamStreamID: s.streamID,
                addedAt: s.added,
                year: s.year,
                rating: s.rating
            )
        }
        return ChannelCollection(channels, groupOrder: categories.map(\.name))
    }

    func groupedSeries(_ list: [XtreamSeries], categories: [XtreamCategory]) -> (series: [XtreamSeries], groups: [String]) {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let series = list.map { s -> XtreamSeries in
            var s = s
            s.group = names[s.categoryID ?? ""] ?? "Sonstige"
            return s
        }
        let used = Set(series.map(\.group))
        var groups = categories.map(\.name).filter { used.contains($0) }
        if used.contains("Sonstige") && !groups.contains("Sonstige") { groups.append("Sonstige") }
        return (series, groups)
    }

    // MARK: Intern

    private func get<T: Decodable & Sendable>(_ type: T.Type, action: String?, extra: [URLQueryItem] = []) async throws -> T {
        guard var comps = URLComponents(string: base + "/player_api.php") else { throw XtreamError.invalidServer }
        var items = [URLQueryItem(name: "username", value: account.username),
                     URLQueryItem(name: "password", value: account.password)]
        if let action { items.append(.init(name: "action", value: action)) }
        comps.queryItems = items + extra
        guard let url = comps.url else { throw XtreamError.invalidServer }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 60))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw XtreamError.http(http.statusCode)
        }
        // Große Listen im Hintergrund dekodieren, damit die Oberfläche flüssig bleibt
        return try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(T.self, from: data)
        }.value
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? s
    }
}

// MARK: - Tolerantes Dekodieren

nonisolated extension KeyedDecodingContainer {
    func flexString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    func flexInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }
}
