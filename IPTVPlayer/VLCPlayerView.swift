import SwiftUI
import UIKit
import VLCKitSPM
#if canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(VLCKit)
import VLCKit
#endif

struct MediaTrack: Identifiable, Hashable {
    let id: Int32
    let name: String
}

/// Steuert den VLC-Player: spielt MKV, TS, MP4 … und kennt alle Ton- und Untertitelspuren
final class VLCPlayerModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()

    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var position: Float = 0
    @Published var timeText = "0:00"
    @Published var remainingText = ""
    @Published var errorText: String?
    @Published var audioTracks: [MediaTrack] = []
    @Published var subtitleTracks: [MediaTrack] = []
    @Published var currentAudio: Int32 = -1
    @Published var currentSubtitle: Int32 = -1

    private let prefAudio: PreferredLanguage
    private let prefSubtitle: PreferredLanguage
    private var didAutoSelect = false
    private var isSeeking = false

    init(url: URL, prefAudio: PreferredLanguage, prefSubtitle: PreferredLanguage) {
        self.prefAudio = prefAudio
        self.prefSubtitle = prefSubtitle
        super.init()

        let media = VLCMedia(url: url)
        media.addOption(url.isFileURL ? ":file-caching=500" : ":network-caching=2000")
        if prefAudio != .none { media.addOption(":audio-language=\(prefAudio.vlcCodes)") }
        if prefSubtitle != .none { media.addOption(":sub-language=\(prefSubtitle.vlcCodes)") }
        player.media = media
        player.delegate = self
    }

    func attach(to view: UIView) { player.drawable = view }

    func play() { player.play() }

    func togglePlay() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func stop() { player.stop() }

    func jump(seconds: Int32) {
        if seconds >= 0 { player.jumpForward(seconds) } else { player.jumpBackward(-seconds) }
    }

    func beginSeek() { isSeeking = true }

    func endSeek(at value: Float) {
        player.position = value
        isSeeking = false
    }

    func selectAudio(_ id: Int32) {
        player.currentAudioTrackIndex = id
        currentAudio = id
    }

    func selectSubtitle(_ id: Int32) {
        player.currentVideoSubTitleIndex = id
        currentSubtitle = id
    }

    // MARK: VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch player.state {
        case .error:
            errorText = "Der Stream konnte nicht geöffnet werden. Prüfe deine Internetverbindung oder ob der Anbieter erreichbar ist."
            isBuffering = false
        case .opening, .buffering:
            if !player.isPlaying { isBuffering = true }
        case .playing:
            isBuffering = false
        case .ended, .stopped:
            isBuffering = false
        default:
            break
        }
        isPlaying = player.isPlaying
        refreshTracks()
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        isBuffering = false
        if !isSeeking { position = player.position }
        timeText = player.time?.stringValue ?? ""
        remainingText = player.remainingTime?.stringValue ?? ""
        if audioTracks.isEmpty && subtitleTracks.isEmpty { refreshTracks() }
    }

    // MARK: Spuren

    private func refreshTracks() {
        audioTracks = Self.tracks(names: player.audioTrackNames, ids: player.audioTrackIndexes)
            .filter { $0.id >= 0 }
        subtitleTracks = Self.tracks(names: player.videoSubTitlesNames, ids: player.videoSubTitlesIndexes)
            .filter { $0.id >= 0 }
        currentAudio = player.currentAudioTrackIndex
        currentSubtitle = player.currentVideoSubTitleIndex
        autoSelectIfNeeded()
    }

    /// Einmalig: bevorzugte Sprache wählen, falls VLC das nicht schon über die Sprachcodes getan hat
    private func autoSelectIfNeeded() {
        guard !didAutoSelect, !audioTracks.isEmpty else { return }
        didAutoSelect = true

        if prefAudio != .none,
           let current = audioTracks.first(where: { $0.id == currentAudio }),
           !prefAudio.matches(current.name),
           let match = audioTracks.first(where: { prefAudio.matches($0.name) }) {
            selectAudio(match.id)
        }

        if prefSubtitle == .none {
            if currentSubtitle >= 0 { selectSubtitle(-1) }
        } else if let match = subtitleTracks.first(where: { prefSubtitle.matches($0.name) }) {
            if match.id != currentSubtitle { selectSubtitle(match.id) }
        }
    }

    private static func tracks(names: [Any]?, ids: [Any]?) -> [MediaTrack] {
        let names = (names ?? []).map { "\($0)" }
        let ids = (ids ?? []).compactMap { ($0 as? NSNumber)?.int32Value }
        return zip(ids, names).map { MediaTrack(id: $0, name: $1) }
    }
}

/// Die Fläche, auf die VLC das Bild zeichnet
struct VLCVideoSurface: UIViewRepresentable {
    let model: VLCPlayerModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Player-Bildschirm für Filme, Serien, Downloads (und optional Live-TV)
struct VLCPlayerScreen: View {
    @EnvironmentObject private var store: PlaylistStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let channel: Channel

    @StateObject private var model: VLCPlayerModel
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var sliderValue: Float = 0
    @State private var isDragging = false
    @State private var epg: [XtreamEPGEntry] = []

    init(channel: Channel) {
        self.channel = channel
        let defaults = UserDefaults.standard
        let audio = PreferredLanguage(rawValue: defaults.string(forKey: SettingsKey.audioLanguage) ?? "") ?? .de
        let subs = PreferredLanguage(rawValue: defaults.string(forKey: SettingsKey.subtitleLanguage) ?? "") ?? .none
        let url = DownloadManager.shared.localFileURL(for: channel) ?? channel.streamURL
        _model = StateObject(wrappedValue: VLCPlayerModel(url: url, prefAudio: audio, prefSubtitle: subs))
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isLive: Bool { channel.kind == .live }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
                .frame(maxWidth: .infinity)
                .frame(maxHeight: isLandscape ? .infinity : nil)
                .aspectRatio(isLandscape ? nil : 16 / 9, contentMode: .fit)
                .background(.black)

            if !isLandscape {
                infoList
            }
        }
        .background(isLandscape ? Color.black : Color.clear)
        .ignoresSafeArea(edges: isLandscape ? .all : [])
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(isLandscape)
        .toolbar {
            if !isLive {
                ToolbarItem(placement: .topBarTrailing) { DownloadButton(channel: channel) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFavorite(channel) } label: {
                    Image(systemName: store.isFavorite(channel) ? "star.fill" : "star")
                }
            }
        }
        .onAppear {
            model.play()
            UIApplication.shared.isIdleTimerDisabled = true
            scheduleHide()
        }
        .onDisappear {
            model.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            hideTask?.cancel()
        }
        .task {
            guard isLive, let id = channel.xtreamStreamID, let client = store.xtreamClient else { return }
            epg = (try? await client.shortEPG(streamID: id)) ?? []
        }
    }

    // MARK: Bild + Bedienelemente

    private var playerArea: some View {
        ZStack {
            VLCVideoSurface(model: model)
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            if model.isBuffering && model.errorText == nil {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if showControls {
                controls
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private var controls: some View {
        ZStack {
            Color.black.opacity(0.35)
                .onTapGesture { toggleControls() }

            // Mitte: zurück / Play / vor
            HStack(spacing: 44) {
                if !isLive {
                    Button { model.jump(seconds: -10); scheduleHide() } label: {
                        Image(systemName: "gobackward.10").font(.title)
                    }
                }
                Button { model.togglePlay(); scheduleHide() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.largeTitle)
                }
                if !isLive {
                    Button { model.jump(seconds: 10); scheduleHide() } label: {
                        Image(systemName: "goforward.10").font(.title)
                    }
                }
            }

            VStack {
                // Oben rechts: Ton & Untertitel
                HStack {
                    Spacer()
                    trackMenu
                }
                .padding(.horizontal, 12)
                .padding(.top, isLandscape ? 16 : 8)

                Spacer()

                // Unten: Zeitleiste
                if !isLive {
                    VStack(spacing: 2) {
                        Slider(value: Binding(
                            get: { isDragging ? sliderValue : model.position },
                            set: { sliderValue = $0 }
                        ), in: 0...1) { editing in
                            isDragging = editing
                            if editing { model.beginSeek(); hideTask?.cancel() }
                            else { model.endSeek(at: sliderValue); scheduleHide() }
                        }
                        HStack {
                            Text(model.timeText)
                            Spacer()
                            Text(model.remainingText)
                        }
                        .font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, isLandscape ? 20 : 8)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var trackMenu: some View {
        Menu {
            Section("Tonspur") {
                if model.audioTracks.isEmpty {
                    Text("Wird geladen …")
                }
                ForEach(model.audioTracks) { track in
                    Button { model.selectAudio(track.id) } label: {
                        if track.id == model.currentAudio { Label(track.name, systemImage: "checkmark") }
                        else { Text(track.name) }
                    }
                }
            }
            Section("Untertitel") {
                Button { model.selectSubtitle(-1) } label: {
                    if model.currentSubtitle < 0 { Label("Aus", systemImage: "checkmark") }
                    else { Text("Aus") }
                }
                ForEach(model.subtitleTracks) { track in
                    Button { model.selectSubtitle(track.id) } label: {
                        if track.id == model.currentSubtitle { Label(track.name, systemImage: "checkmark") }
                        else { Text(track.name) }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.title3)
                .padding(10)
                .background(.black.opacity(0.4), in: Circle())
        }
    }

    private func toggleControls() {
        showControls.toggle()
        if showControls { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled && model.isPlaying && !isDragging {
                showControls = false
            }
        }
    }

    // MARK: Infos unter dem Bild

    private var infoList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.title3.bold())
                    Text(channel.group).foregroundStyle(.secondary)
                    if DownloadManager.shared.localFileURL(for: channel) != nil {
                        Label("Wird offline abgespielt", systemImage: "arrow.down.circle.fill")
                            .font(.footnote).foregroundStyle(.green)
                    }
                }
            }

            if let error = model.errorText {
                Section("Wiedergabe nicht möglich") { Text(error) }
            }

            if !model.audioTracks.isEmpty || !model.subtitleTracks.isEmpty {
                Section("Ton & Untertitel") {
                    Picker("Tonspur", selection: Binding(
                        get: { model.currentAudio },
                        set: { model.selectAudio($0) }
                    )) {
                        ForEach(model.audioTracks) { Text($0.name).tag($0.id) }
                    }
                    Picker("Untertitel", selection: Binding(
                        get: { model.currentSubtitle },
                        set: { model.selectSubtitle($0) }
                    )) {
                        Text("Aus").tag(Int32(-1))
                        ForEach(model.subtitleTracks) { Text($0.name).tag($0.id) }
                    }
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

            Section {
                Text("Tipp: iPhone quer halten für Vollbild. Bevorzugte Sprache und Untertitel stellst du in den Einstellungen (Zahnrad) ein.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
