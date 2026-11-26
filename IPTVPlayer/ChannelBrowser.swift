import SwiftUI

/// Liste für Live-TV oder Filme: Suche, Kategorie-Filter, Favoriten, Listen-/Kachelansicht
struct ChannelBrowser: View {
    @EnvironmentObject private var store: PlaylistStore
    @EnvironmentObject private var downloads: DownloadManager
    let title: String
    let collection: ChannelCollection
    @Binding var showSettings: Bool

    @State private var search = ""
    @State private var selectedGroup: String?
    @State private var favoritesOnly = false
    @AppStorage private var useGrid: Bool
    @AppStorage private var sortOrder: SortOrder
    @State private var shuffleSeed = Int.random(in: 0...Int.max)
    @State private var path = NavigationPath()
    @State private var showRandom = false

    init(title: String, collection: ChannelCollection, showSettings: Binding<Bool>) {
        self.title = title
        self.collection = collection
        _showSettings = showSettings
        // Jeder Tab merkt sich seine Ansicht und Sortierung; Filme starten mit großen Titelbildern
        _useGrid = AppStorage(wrappedValue: title != "Live-TV", "gridLayout.\(title)")
        _sortOrder = AppStorage(wrappedValue: .provider, "sortOrder.\(title)")
    }

    private var filtered: [Channel] {
        let items = collection.channels.filter { ch in
            (!favoritesOnly || store.isFavorite(ch))
            && (selectedGroup == nil || ch.group == selectedGroup)
            && (search.isEmpty || ch.name.localizedCaseInsensitiveContains(search))
        }
        return sortOrder.apply(items, seed: shuffleSeed, id: \.id, name: \.name, date: \.addedAt)
    }

    private var randomCandidates: [RandomCandidate] {
        collection.channels.map {
            RandomCandidate(id: $0.id, title: $0.name, group: $0.group, imageURL: $0.logoURL,
                            year: $0.year, rating: $0.rating)
        }
    }

    private var isLiveTab: Bool { collection.channels.first?.kind == .live }

    var body: some View {
        NavigationStack(path: $path) {
            let items = filtered
            Group {
                if useGrid {
                    grid(items)
                } else {
                    list(items)
                }
            }
            .overlay {
                if items.isEmpty {
                    if !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView("Keine Einträge", systemImage: favoritesOnly ? "star" : "tray",
                                               description: Text(favoritesOnly ? "Wische einen Eintrag nach links oder halte ihn gedrückt, um ihn zu favorisieren." : ""))
                    }
                }
            }
            .searchable(text: $search, prompt: "Suchen")
            .navigationTitle(favoritesOnly ? "Favoriten" : (selectedGroup ?? title))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Channel.self) { PlayerView(channel: $0) }
            .refreshable { await store.reload() }
            .sheet(isPresented: $showRandom) {
                RandomPickView(title: "Zufälliger Film", candidates: randomCandidates,
                               groups: collection.groups) { id in
                    if let ch = collection.channels.first(where: { $0.id == id }) { path.append(ch) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Nur Favoriten", isOn: $favoritesOnly)
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
                            ForEach(collection.groups, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        Image(systemName: selectedGroup == nil && !favoritesOnly
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                if !isLiveTab {
                    ToolbarItem(placement: .topBarTrailing) {
                        RandomButton { showRandom = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    LayoutToggle(useGrid: $useGrid)
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(showSettings: $showSettings) }
            }
        }
    }

    // MARK: Listenansicht

    private func list(_ items: [Channel]) -> some View {
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
    }

    // MARK: Kachelansicht mit großen Titelbildern

    private func grid(_ items: [Channel]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: isLiveTab ? 150 : 110), spacing: 12)], spacing: 16) {
                ForEach(items) { ch in
                    NavigationLink(value: ch) {
                        PosterTile(title: ch.name,
                                   imageURL: ch.logoURL,
                                   isFavorite: store.isFavorite(ch),
                                   style: isLiveTab ? .logo : .poster)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { store.toggleFavorite(ch) } label: {
                            Label(store.isFavorite(ch) ? "Favorit entfernen" : "Zu Favoriten",
                                  systemImage: store.isFavorite(ch) ? "star.slash" : "star")
                        }
                        if ch.kind != .live && downloads.item(for: ch) == nil {
                            Button { downloads.start(ch) } label: {
                                Label("Herunterladen", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

/// Umschalter Liste ⇄ Kacheln
struct LayoutToggle: View {
    @Binding var useGrid: Bool
    var body: some View {
        Button {
            withAnimation { useGrid.toggle() }
        } label: {
            Image(systemName: useGrid ? "list.bullet" : "square.grid.2x2")
        }
        .accessibilityLabel(useGrid ? "Listenansicht" : "Kachelansicht")
    }
}

/// Eine Kachel: Filmplakat (hochkant) oder Senderlogo (quer)
struct PosterTile: View {
    enum Style { case poster, logo }

    let title: String
    let imageURL: URL?
    var isFavorite = false
    var style: Style = .poster

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(uiColor: .secondarySystemBackground)
                .aspectRatio(style == .poster ? 2 / 3 : 16 / 9, contentMode: .fit)
                .overlay {
                    AsyncImage(url: imageURL) { image in
                        if style == .poster {
                            image.resizable().scaledToFill()
                        } else {
                            image.resizable().scaledToFit().padding(12)
                        }
                    } placeholder: {
                        Image(systemName: style == .poster ? "film" : "tv")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(6)
                    }
                }

            Text(title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
