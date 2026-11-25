import SwiftUI
import AVKit

@MainActor
final class PlayerModel: ObservableObject {
    let player: AVPlayer
    @Published var errorText: String?
    private var statusTask: Task<Void, Never>?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        statusTask = Task { [weak self] in
            for await status in item.publisher(for: \.status).values where status == .failed {
                self?.errorText = item.error?.localizedDescription ?? "Unbekannter Fehler"
            }
        }
    }

    func stop() {
        player.pause()
        statusTask?.cancel()
    }
}

struct PlayerView: View {
    @EnvironmentObject private var store: PlaylistStore
    let channel: Channel
    @StateObject private var model: PlayerModel
    @State private var epg: [XtreamEPGEntry] = []

    init(channel: Channel) {
        self.channel = channel
        // Heruntergeladene Datei wird offline abgespielt
        let url = DownloadManager.shared.localFileURL(for: channel) ?? channel.streamURL
        _model = StateObject(wrappedValue: PlayerModel(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            AVPlayerControllerView(player: model.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)

            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name).font(.title3.bold())
                        Text(channel.group).foregroundStyle(.secondary)
                    }
                }

                if let error = model.errorText {
                    Section("Wiedergabe nicht möglich") {
                        Text(error)
                        Text("Formate wie .ts oder .mkv kann der iOS-Player nicht abspielen. Dafür bauen wir als Nächstes VLCKit ein.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !epg.isEmpty {
                    Section("Programm") {
                        ForEach(epg) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    if let start = entry.start {
                                        Text(start.formatted(date: .omitted, time: .shortened))
                                            .monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    Text(entry.title).bold().lineLimit(1)
                                }
                                if !entry.description.isEmpty {
                                    Text(entry.description).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if channel.kind != .live {
                ToolbarItem(placement: .topBarTrailing) { DownloadButton(channel: channel) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFavorite(channel) } label: {
                    Image(systemName: store.isFavorite(channel) ? "star.fill" : "star")
                }
            }
        }
        .onAppear { model.player.play() }
        .onDisappear { model.stop() }
        .task {
            guard channel.kind == .live, let id = channel.xtreamStreamID, let client = store.xtreamClient else { return }
            epg = (try? await client.shortEPG(streamID: id)) ?? []
        }
    }
}

/// Apples nativer Player: Vollbild, AirPlay, Bild-in-Bild inklusive
struct AVPlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
