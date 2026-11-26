import SwiftUI

/// Xtream-Serien: Liste → Staffeln → Folgen
struct SeriesBrowser: View {
    @EnvironmentObject private var store: PlaylistStore
    @Binding var showSettings: Bool
    @State private var search = ""
    @State private var selectedGroup: String?
    @AppStorage("gridLayout.Serien") private var useGrid = true
    @AppStorage("sortOrder.Serien") private var sortOrder: SortOrder = .provider
    @State private var shuffleSeed = Int.random(in: 0...Int.max)
    @State private var path = NavigationPath()
    @State private var showRandom = false

    private var filtered: [XtreamSeries] {
        let items = store.series.filter { s in
            (selectedGroup == nil || s.group == selectedGroup)
            && (search.isEmpty || s.name.localizedCaseInsensitiveContains(search))
        }
        return sortOrder.apply(items, seed: shuffleSeed, id: { String($0.id) }, name: \.name, date: \.lastModified)
    }

    private var randomCandidates: [RandomCandidate] {
        store.series.map {
            RandomCandidate(id: String($0.id), title: $0.name, group: $0.group,
                            imageURL: $0.cover.flatMap(URL.init(string:)), year: $0.year, rating: $0.rating)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if useGrid {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                            ForEach(filtered) { s in
                                NavigationLink(value: s) {
                                    PosterTile(title: s.name, imageURL: s.cover.flatMap(URL.init(string:)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                } else {
                    List(filtered) { s in
                        NavigationLink(value: s) {
                            PosterRow(title: s.name, subtitle: s.group, imageURL: s.cover.flatMap(URL.init(string:)))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: "Serien suchen")
            .navigationTitle(selectedGroup ?? "Serien")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: XtreamSeries.self) { SeriesDetailView(series: $0) }
            .navigationDestination(for: Channel.self) { PlayerView(channel: $0) }
            .sheet(isPresented: $showRandom) {
                RandomPickView(title: "Zufällige Serie", candidates: randomCandidates,
                               groups: store.seriesGroups) { id in
                    if let s = store.series.first(where: { String($0.id) == id }) { path.append(s) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                        } label: {
                            Label("Sortierung: \(sortOrder.title)", systemImage: "arrow.up.arrow.down")
                        }
                        .pickerStyle(.menu)
                        if sortOrder == .random {
                            Button { shuffleSeed = Int.random(in: 0...Int.max) } label: {
                                Label("Neu mischen", systemImage: "shuffle")
                            }
                        }
                        Picker("Kategorie", selection: $selectedGroup) {
                            Text("Alle Kategorien").tag(String?.none)
                            ForEach(store.seriesGroups, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        Image(systemName: selectedGroup == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { RandomButton { showRandom = true } }
                ToolbarItem(placement: .topBarTrailing) { LayoutToggle(useGrid: $useGrid) }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(showSettings: $showSettings) }
            }
        }
    }
}

struct SeriesDetailView: View {
    @EnvironmentObject private var store: PlaylistStore
    @ObservedObject private var history = WatchHistory.shared
    let series: XtreamSeries
    @State private var info: XtreamSeriesInfo?
    @State private var error: String?

    var body: some View {
        List {
            if let plot = series.plot, !plot.isEmpty {
                Section { Text(plot).font(.callout) }
            }
            if let info, let client = store.xtreamClient {
                ForEach(info.seasons) { season in
                    Section("Staffel \(season.season)") {
                        ForEach(season.episodes) { ep in
                            if let url = client.episodeURL(ep.id, ext: ep.containerExtension) {
                                let channel = Channel(
                                    id: "episode-\(ep.id)", name: ep.title, group: series.name,
                                    logoURL: series.cover.flatMap(URL.init(string:)), streamURL: url, kind: .episode,
                                    seriesID: series.id, seriesName: series.name,
                                    seriesCover: series.cover.flatMap(URL.init(string:)),
                                    season: season.season, episode: ep.episodeNum)
                                NavigationLink(value: channel) {
                                    HStack {
                                        Text("\(ep.episodeNum). \(ep.title)").lineLimit(2)
                                        Spacer()
                                        if let e = history.entry(for: channel) {
                                            if e.isFinished {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                            } else {
                                                Text("\(Int(e.progress * 100)) %")
                                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard info == nil, let client = store.xtreamClient else { return }
            do { info = try await client.seriesInfo(id: series.id) }
            catch { self.error = error.localizedDescription }
        }
    }
}
