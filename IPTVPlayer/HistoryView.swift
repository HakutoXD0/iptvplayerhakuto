import SwiftUI

/// Tab „Weiterschauen“: angefangene Filme/Folgen + aktuelle Serien
struct HistoryView: View {
    @EnvironmentObject private var store: PlaylistStore
    @ObservedObject private var history = WatchHistory.shared
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            List {
                let continueItems = history.continueWatching
                if !continueItems.isEmpty {
                    Section("Weiterschauen") {
                        ForEach(continueItems) { e in
                            NavigationLink(value: e.asChannel) {
                                HistoryRow(title: e.seriesName ?? e.name,
                                           subtitle: e.seriesName != nil ? e.episodeLabel : e.group,
                                           imageURL: e.seriesCover ?? e.logoURL,
                                           progress: e.progress,
                                           detail: e.remainingText)
                            }
                            .swipeActions {
                                Button(role: .destructive) { history.remove(e) } label: {
                                    Label("Entfernen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                let series = history.currentSeries
                if !series.isEmpty {
                    Section("Meine Serien") {
                        ForEach(series) { e in
                            NavigationLink(value: e.asChannel) {
                                HistoryRow(title: e.seriesName ?? e.group,
                                           subtitle: (e.isFinished ? "Gesehen: " : "Zuletzt: ") + e.episodeLabel,
                                           imageURL: e.seriesCover ?? e.logoURL,
                                           progress: e.progress,
                                           detail: e.isFinished ? "Folge fertig – nächste in der Serie wählen" : e.remainingText)
                            }
                            .contextMenu {
                                if let s = store.series.first(where: { $0.id == e.seriesID }) {
                                    NavigationLink(value: s) { Label("Alle Folgen anzeigen", systemImage: "list.bullet") }
                                }
                            }
                            .swipeActions {
                                if let s = store.series.first(where: { $0.id == e.seriesID }) {
                                    NavigationLink(value: s) { Label("Folgen", systemImage: "list.bullet") }
                                        .tint(.blue)
                                }
                                Button(role: .destructive) {
                                    if let id = e.seriesID { history.removeSeries(id) }
                                } label: {
                                    Label("Entfernen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if history.continueWatching.isEmpty && history.currentSeries.isEmpty {
                    ContentUnavailableView("Noch nichts angefangen", systemImage: "clock.arrow.circlepath",
                                           description: Text("Filme und Folgen, die du anschaust, erscheinen hier – und laufen beim nächsten Mal an der richtigen Stelle weiter."))
                }
            }
            .navigationTitle("Weiterschauen")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Channel.self) { PlayerView(channel: $0) }
            .navigationDestination(for: XtreamSeries.self) { SeriesDetailView(series: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(showSettings: $showSettings) }
            }
        }
    }
}

struct HistoryRow: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let progress: Double
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "film").foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 76)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                ProgressView(value: progress).tint(.accentColor)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
