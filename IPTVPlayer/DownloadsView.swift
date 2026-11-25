import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(downloads.items) { item in
                    row(item)
                        .swipeActions {
                            Button(role: .destructive) { downloads.delete(item) } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .overlay {
                if downloads.items.isEmpty {
                    ContentUnavailableView("Keine Downloads", systemImage: "arrow.down.circle",
                                           description: Text("Öffne einen Film oder eine Folge und tippe auf den Download-Pfeil."))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !downloads.items.isEmpty {
                    Text("Belegt: \(ByteCountFormatter.string(fromByteCount: downloads.usedBytes, countStyle: .file))")
                        .font(.footnote).foregroundStyle(.secondary).padding(8)
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Channel.self) { PlayerView(channel: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton(showSettings: $showSettings) }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: DownloadItem) -> some View {
        switch item.state {
        case .finished:
            NavigationLink(value: item.asChannel) {
                PosterRow(title: item.name, subtitle: item.group, imageURL: item.logoURL)
            }
        case .downloading:
            VStack(alignment: .leading, spacing: 6) {
                PosterRow(title: item.name, subtitle: item.group, imageURL: item.logoURL)
                ProgressView(value: downloads.progress[item.id] ?? 0)
            }
        case .failed:
            HStack {
                PosterRow(title: item.name, subtitle: "Fehlgeschlagen", imageURL: item.logoURL)
                Button("Erneut") { downloads.start(item.asChannel) }
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// Download-Knopf für den Player
struct DownloadButton: View {
    @EnvironmentObject private var downloads: DownloadManager
    let channel: Channel

    var body: some View {
        switch downloads.item(for: channel)?.state {
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .downloading:
            ProgressView(value: downloads.progress[channel.id] ?? 0)
                .progressViewStyle(.circular)
        case .failed, nil:
            Button { downloads.start(channel) } label: { Image(systemName: "arrow.down.circle") }
        }
    }
}
