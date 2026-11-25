import SwiftUI

/// Xtream-Serien: Liste → Staffeln → Folgen
struct SeriesBrowser: View {
    @EnvironmentObject private var store: PlaylistStore
    @Binding var showSettings: Bool
    @State private var search = ""
    @State private var selectedGroup: String?

    private var filtered: [XtreamSeries] {
        store.series.filter { s in
            (selectedGroup == nil || s.group == selectedGroup)
            && (search.isEmpty || s.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { s in
                NavigationLink(value: s) {
                    PosterRow(title: s.name, subtitle: s.group, imageURL: s.cover.flatMap(URL.init(string:)))
                }
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: "Serien suchen")
            .navigationTitle(selectedGroup ?? "Serien")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: XtreamSeries.self) { SeriesDetailView(series: $0) }
            .navigationDestination(for: Channel.self) { PlayerView(channel: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Kategorie", selection: $selectedGroup) {
                            Text("Alle Kategorien").tag(String?.none)
                            ForEach(store.seriesGroups, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        Image(systemName: selectedGroup == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(showSettings: $showSettings) }
            }
        }
    }
}

struct SeriesDetailView: View {
    @EnvironmentObject private var store: PlaylistStore
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
                                NavigationLink(value: Channel(
                                    id: "episode-\(ep.id)", name: ep.title, group: series.name,
                                    logoURL: series.cover.flatMap(URL.init(string:)), streamURL: url, kind: .episode
                                )) {
                                    Text("\(ep.episodeNum). \(ep.title)").lineLimit(2)
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
