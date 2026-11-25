import SwiftUI

/// Liste für Live-TV oder Filme: Suche, Kategorie-Filter, Favoriten
struct ChannelBrowser: View {
    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var downloads: DownloadManager
    let title: String
    let collection: ChannelCollection
    @Binding var showSettings: Bool

    @State private var search = ""
    @State private var selectedGroup: String?
    @State private var favoritesOnly = false

    private var filtered: [Channel] {
        collection.channels.filter { ch in
            (!favoritesOnly || store.isFavorite(ch))
            && (selectedGroup == nil || ch.group == selectedGroup)
            && (search.isEmpty || ch.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            let items = filtered
            List(items) { ch in
                NavigationLink(value: ch) {
                    PosterRow(title: ch.name, subtitle: ch.group, imageURL: ch.logoURL, isFavorite: store.isFavorite(ch))
                }
                .swipeActions {
                    Button { store.toggleFavorite(ch) } label: {
                        Label("Favorit", systemImage: store.isFavorite(ch) ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                    if ch.kind != .live && downloads.item(for: ch) == nil {
                        Button { downloads.start(ch) } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if items.isEmpty {
                    if !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView("Keine Einträge", systemImage: favoritesOnly ? "star" : "tray",
                                               description: Text(favoritesOnly ? "Wische einen Eintrag nach links, um ihn zu favorisieren." : ""))
                    }
                }
            }
            .searchable(text: $search, prompt: "Suchen")
            .navigationTitle(favoritesOnly ? "Favoriten" : (selectedGroup ?? title))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Channel.self) { PlayerView(channel: $0) }
            .refreshable { await store.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Nur Favoriten", isOn: $favoritesOnly)
                        Picker("Kategorie", selection: $selectedGroup) {
                            Text("Alle Kategorien").tag(String?.none)
                            ForEach(collection.groups, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        Image(systemName: selectedGroup == nil && !favoritesOnly
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(showSettings: $showSettings) }
            }
        }
    }
}
