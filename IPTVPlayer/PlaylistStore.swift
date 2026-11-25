import Foundation

nonisolated enum PlaylistSource: Codable, Hashable, Sendable {
    case m3u(String)              // http(s)- oder file://-URL
    case xtream(XtreamAccount)
}

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var source: PlaylistSource?
    @Published private(set) var live = ChannelCollection()
    @Published private(set) var movies = ChannelCollection()
    @Published private(set) var series: [XtreamSeries] = []
    @Published private(set) var seriesGroups: [String] = []
    @Published private(set) var userInfo: XtreamUserInfo?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var favorites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") }
    }

    var xtreamClient: XtreamClient? {
        if case .xtream(let account) = source { XtreamClient(account: account) } else { nil }
    }

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        if let data = Keychain.load(account: "source"),
           let saved = try? JSONDecoder().decode(PlaylistSource.self, from: data) {
            source = saved
        }
    }

    // MARK: Quelle verbinden / laden

    /// Lädt die neue Quelle und speichert sie nur, wenn das Laden geklappt hat
    @discardableResult
    func connect(_ newSource: PlaylistSource) async -> Bool {
        guard await load(newSource) else { return false }
        source = newSource
        if let data = try? JSONEncoder().encode(newSource) { Keychain.save(data, account: "source") }
        return true
    }

    func reload() async {
        if let source { await load(source) }
    }

    /// M3U-Datei aus der Dateien-App übernehmen (wird in die App kopiert)
    @discardableResult
    func importM3UFile(_ picked: URL) async -> Bool {
        let access = picked.startAccessingSecurityScopedResource()
        defer { if access { picked.stopAccessingSecurityScopedResource() } }
        do {
            let target = URL.documentsDirectory.appending(path: "import.m3u")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: picked, to: target)
            return await connect(.m3u(target.absoluteString))
        } catch {
            errorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
            return false
        }
    }

    func disconnect() {
        Keychain.delete(account: "source")
        source = nil
        live = .init(); movies = .init(); series = []; seriesGroups = []; userInfo = nil
        errorMessage = nil
    }

    @discardableResult
    private func load(_ source: PlaylistSource) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            switch source {
            case .m3u(let urlString):
                live = try await loadM3U(urlString)
                movies = .init(); series = []; seriesGroups = []; userInfo = nil

            case .xtream(let account):
                let client = XtreamClient(account: account)
                let info = try await client.authenticate()

                async let liveCats = client.liveCategories()
                async let liveStreams = client.liveStreams()
                async let vodCats = client.vodCategories()
                async let vodStreams = client.vodStreams()
                async let seriesCats = client.seriesCategories()
                async let seriesList = client.series()

                // Live muss klappen, Filme/Serien sind optional
                let (lc, ls) = try await (liveCats, liveStreams)
                live = client.collection(streams: ls, categories: lc, kind: .live)

                if let vc = try? await vodCats, let vs = try? await vodStreams {
                    movies = client.collection(streams: vs, categories: vc, kind: .movie)
                } else {
                    movies = .init()
                }

                if let sc = try? await seriesCats, let sl = try? await seriesList {
                    (series, seriesGroups) = client.groupedSeries(sl, categories: sc)
                } else {
                    series = []; seriesGroups = []
                }
                userInfo = info
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadM3U(_ urlString: String) async throws -> ChannelCollection {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.isFileURL || url.scheme?.hasPrefix("http") == true else {
            throw URLError(.badURL)
        }
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (d, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 60))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw XtreamError.http(http.statusCode)
            }
            data = d
        }
        let channels = await Task.detached(priority: .userInitiated) {
            M3UParser.parse(String(decoding: data, as: UTF8.self))
        }.value
        guard !channels.isEmpty else {
            throw NSError(domain: "IPTV", code: 1, userInfo: [NSLocalizedDescriptionKey: "In der Playlist wurden keine Sender gefunden."])
        }
        return ChannelCollection(channels)
    }

    // MARK: Favoriten

    func isFavorite(_ channel: Channel) -> Bool { favorites.contains(channel.favoriteKey) }

    func toggleFavorite(_ channel: Channel) {
        if favorites.contains(channel.favoriteKey) { favorites.remove(channel.favoriteKey) }
        else { favorites.insert(channel.favoriteKey) }
    }
}
