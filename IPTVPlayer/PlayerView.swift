import SwiftUI
import AVKit

@MainActor
final class PlayerModel: ObservableObject {
    let player: AVPlayer
    @Published var errorText: String?
    @Published var reconnects = 0

    private let url: URL
    private let maxResolution: CGSize
    private var statusTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var historyChannel: Channel?
    private var watchdogTask: Task<Void, Never>?
    private var lastTime: Double = -1
    private var stuckSince: Date?

    init(url: URL, maxResolution: CGSize = .zero, isLive: Bool = true, preferredLanguage: String? = nil) {
        self.url = url
        self.maxResolution = maxResolution
        player = AVPlayer()
        if let preferredLanguage {
            // Bevorzugte Tonspur bei MP4-Dateien mit mehreren Sprachen
            player.setMediaSelectionCriteria(
                AVPlayerMediaSelectionCriteria(preferredLanguages: [preferredLanguage], preferredMediaCharacteristics: nil),
                forMediaCharacteristic: .audible)
        }
        loadItem()
        if isLive { startWatchdog() }
    }

    /// Verlauf für Filme/Folgen: an alter Stelle weitermachen + alle 5 s merken
    func enableHistory(for channel: Channel) {
        guard channel.kind != .live else { return }
        historyChannel = channel
        if let start = WatchHistory.shared.resumePosition(for: channel) {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1),
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
    }

    func saveProgress() {
        guard let channel = historyChannel, let item = player.currentItem else { return }
        let pos = player.currentTime().seconds
        let dur = item.duration.seconds
        guard pos.isFinite, dur.isFinite, dur > 0 else { return }
        WatchHistory.shared.update(channel: channel, position: pos, duration: dur)
    }

    /// Neues Item = frische Verbindung, springt bei Live wieder an die aktuelle Stelle
    private func loadItem() {
        let item = AVPlayerItem(url: url)
        // Begrenzt die Qualität, wenn der Sender mehrere Stufen anbietet
        item.preferredMaximumResolution = maxResolution
        // Etwas mehr Puffer gegen kurze Aussetzer
        item.preferredForwardBufferDuration = 8
        player.replaceCurrentItem(with: item)

        statusTask?.cancel()
        statusTask = Task { [weak self] in
            for await status in item.publisher(for: \.status).values where status == .failed {
                self?.errorText = item.error?.localizedDescription ?? "Unbekannter Fehler"
            }
        }
    }

    /// Erkennt hängende Streams und verbindet automatisch neu
    /// (statt dass man selbst Pause/Play drücken muss)
    private func startWatchdog() {
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.checkForStall()
            }
        }
    }

    private func checkForStall() {
        // Vom Nutzer pausiert → nichts tun
        guard player.timeControlStatus != .paused || player.rate != 0 else {
            stuckSince = nil
            return
        }
        let now = player.currentTime().seconds
        let advancing = now.isFinite && now != lastTime
        lastTime = now

        if advancing && player.timeControlStatus == .playing {
            stuckSince = nil
            return
        }
        if stuckSince == nil {
            stuckSince = Date()
        } else if let since = stuckSince, Date().timeIntervalSince(since) > 6 {
            reconnect()
        }
    }

    private func reconnect() {
        stuckSince = nil
        lastTime = -1
        reconnects += 1
        loadItem()
        player.play()
    }

    func stop() {
        saveProgress()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        statusTask?.cancel()
        watchdogTask?.cancel()
    }
}

/// Wählt den passenden Player: Live-TV → Apple-Player (Bild-in-Bild, AirPlay),
/// Filme/Serien/Downloads → VLC (kann MKV, mehrere Tonspuren, Untertitel)
struct PlayerView: View {
    let channel: Channel
    @AppStorage(SettingsKey.liveUseVLC) private var liveUseVLC = false

    /// Formate, die Apples Player kann – dort gibt es Bild-in-Bild und AirPlay
    private static let nativeFormats: Set<String> = ["mp4", "m4v", "mov", "m3u8"]

    private var useNative: Bool {
        if channel.kind == .live { return !liveUseVLC }
        let url = DownloadManager.shared.localFileURL(for: channel) ?? channel.streamURL
        return Self.nativeFormats.contains(url.pathExtension.lowercased())
    }

    var body: some View {
        if useNative {
            NativePlayerView(channel: channel)
        } else {
            VLCPlayerScreen(channel: channel)
        }
    }
}

/// Apples Player für Live-TV (HLS)
struct NativePlayerView: View {
    @EnvironmentObject private var store: PlaylistStore
    let channel: Channel
    @StateObject private var model: PlayerModel
    @State private var epg: [XtreamEPGEntry] = []

    init(channel: Channel) {
        self.channel = channel
        let url = DownloadManager.shared.localFileURL(for: channel) ?? channel.streamURL
        let defaults = UserDefaults.standard
        let quality = LiveQuality(rawValue: defaults.string(forKey: SettingsKey.liveQuality) ?? "") ?? .auto
        let audio = PreferredLanguage(rawValue: defaults.string(forKey: SettingsKey.audioLanguage) ?? "") ?? .de
        let isLive = channel.kind == .live
        _model = StateObject(wrappedValue: PlayerModel(
            url: url,
            maxResolution: isLive ? quality.maxResolution : .zero,
            isLive: isLive,
            preferredLanguage: audio == .none ? nil : audio.isoCode))
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
                        Text("Tipp: In den Einstellungen „Live-TV mit VLC abspielen“ einschalten – VLC kann mehr Formate.")
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
        .onAppear {
            model.enableHistory(for: channel)
            model.player.play()
        }
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
