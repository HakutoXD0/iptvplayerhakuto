import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlaylistStore
    @State private var showSettings = false

    var body: some View {
        // Downloads-Tab ist immer da – so geht's auch ohne Internet
        TabView {
            liveTab
                .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }

            if !store.movies.channels.isEmpty {
                ChannelBrowser(title: "Filme", collection: store.movies, showSettings: $showSettings)
                    .tabItem { Label("Filme", systemImage: "film") }
            }

            if !store.series.isEmpty {
                SeriesBrowser(showSettings: $showSettings)
                    .tabItem { Label("Serien", systemImage: "play.rectangle.on.rectangle") }
            }

            if !store.movies.channels.isEmpty || !store.series.isEmpty {
                HistoryView(showSettings: $showSettings)
                    .tabItem { Label("Weiterschauen", systemImage: "clock.arrow.circlepath") }
            }

            DownloadsView(showSettings: $showSettings)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            if store.live.channels.isEmpty { await store.reload() }
        }
    }

    @ViewBuilder
    private var liveTab: some View {
        if store.source == nil {
            ContentUnavailableView {
                Label("Noch keine Playlist", systemImage: "tv")
            } description: {
                Text("Melde dich mit Xtream Codes an oder füge eine M3U-Playlist hinzu.")
            } actions: {
                Button("Playlist hinzufügen") { showSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.live.channels.isEmpty && store.isLoading {
            ProgressView("Lade Sender …")
        } else if store.live.channels.isEmpty, let error = store.errorMessage {
            ContentUnavailableView {
                Label("Laden fehlgeschlagen", systemImage: "wifi.exclamationmark")
            } description: {
                Text("\(error)\n\nDeine Downloads kannst du trotzdem offline schauen.")
            } actions: {
                Button("Erneut versuchen") { Task { await store.reload() } }
                    .buttonStyle(.borderedProminent)
                Button("Einstellungen") { showSettings = true }
            }
        } else {
            ChannelBrowser(title: "Live-TV", collection: store.live, showSettings: $showSettings)
        }
    }
}

struct SettingsButton: View {
    @Binding var showSettings: Bool
    var body: some View {
        Button { showSettings = true } label: { Image(systemName: "gearshape") }
    }
}

/// Eine Zeile mit Logo/Cover, Titel und Untertitel
struct PosterRow: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    var isFavorite = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: imageURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "tv").foregroundStyle(.secondary)
            }
            .frame(width: 48, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isFavorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
            }
        }
    }
}
