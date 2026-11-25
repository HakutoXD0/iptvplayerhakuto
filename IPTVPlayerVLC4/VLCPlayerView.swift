import SwiftUI
import UIKit
import VLCKit

// ⚠️ BETA: Variante für VLCKit 4 (Vorabversion) – mit Bild-in-Bild auch für MKV

struct MediaTrack: Identifiable, Hashable {
    let id: Int32
    let name: String
}

/// Steuert den VLC-4-Player inkl. Bild-in-Bild
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
    @Published var canPictureInPicture = false
    @Published var isInPictureInPicture = false

    /// Wird von VLC übergeben, sobald Bild-in-Bild bereit ist
    var pipController: VLCPictureInPictureWindowControlling? {
        didSet { canPictureInPicture = pipController != nil }
    }

    private let prefAudio: PreferredLanguage
    private let prefSubtitle: PreferredLanguage
    private var didAutoSelect = false
    private var isSeeking = false

    init(url: URL, prefAudio: PreferredLanguage, prefSubtitle: PreferredLanguage) {
        self.prefAudio = prefAudio
        self.prefSubtitle = prefSubtitle
        super.init()

        let media = VLCMedia(url: url)
        media?.addOption(url.isFileURL ? ":file-caching=500" : ":network-caching=2000")
        if prefAudio != .none { media?.addOption(":audio-language=\(prefAudio.vlcCodes)") }
        if prefSubtitle != .none { media?.addOption(":sub-language=\(prefSubtitle.vlcCodes)") }
        player.media = media
        player.delegate = self
    }

    /// Eine einzige Bildfläche pro Wiedergabe – wird nie ausgetauscht
    lazy var surfaceView: VLCContainerView = {
        let view = VLCContainerView()
        view.backgroundColor = .black
        // Wichtig: sonst fängt VLCs Bildfläche alle Fingertipps ab
        view.isUserInteractionEnabled = false
        view.model = self
        player.drawable = view
        return view
    }()

    func play() { player.play() }

    func togglePlay() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func stop() { player.stop() }

    func jump(seconds: Int32) {
        // Über die Position springen – unabhängig von API-Änderungen in VLCKit 4
        let lengthMs = Double(player.media?.length.intValue ?? 0)
        guard lengthMs > 0 else { return }
        let current = Double(player.position)
        let target = min(max(current + Double(seconds) * 1000 / lengthMs, 0), 1)
        player.position = .init(target)
    }

    func beginSeek() { isSeeking = true }

    func endSeek(at value: Float) {
        player.position = .init(value)
        isSeeking = false
    }

    func selectAudio(_ id: Int32) {
        let tracks = player.audioTracks
        guard tracks.indices.contains(Int(id)) else { return }
        tracks[Int(id)].isSelectedExclusively = true
        currentAudio = id
    }

    func selectSubtitle(_ id: Int32) {
        let tracks = player.textTracks
        if id < 0 {
            player.deselectAllTextTracks()
        } else if tracks.indices.contains(Int(id)) {
            tracks[Int(id)].isSelectedExclusively = true
        }
        currentSubtitle = id
    }

    func togglePictureInPicture() {
        guard let pip = pipController else { return }
        if isInPictureInPicture { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }

    // MARK: VLCMediaPlayerDelegate (VLCKit 4)

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        switch newState {
        case .error:
            errorText = "Der Stream konnte nicht geöffnet werden. Prüfe deine Internetverbindung oder ob der Anbieter erreichbar ist."
            isBuffering = false
        case .opening, .buffering:
            if !player.isPlaying { isBuffering = true }
        case .playing:
            isBuffering = false
        default:
            isBuffering = false
        }
        isPlaying = player.isPlaying
        refreshTracks()
        pipController?.invalidatePlaybackState()
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        isBuffering = false
        isPlaying = player.isPlaying
        if !isSeeking { position = Float(player.position) }
        let time: VLCTime? = player.time
        let remaining: VLCTime? = player.remainingTime
        timeText = time?.stringValue ?? ""
        remainingText = remaining?.stringValue ?? ""
        if audioTracks.isEmpty && subtitleTracks.isEmpty { refreshTracks() }
    }

    // MARK: Spuren

    private func refreshTracks() {
        let audio = player.audioTracks
        let text = player.textTracks
        audioTracks = audio.enumerated().map { MediaTrack(id: Int32($0.offset), name: $0.element.trackName) }
        subtitleTracks = text.enumerated().map { MediaTrack(id: Int32($0.offset), name: $0.element.trackName) }
        currentAudio = Int32(audio.firstIndex(where: { $0.isSelected }) ?? -1)
        currentSubtitle = Int32(text.firstIndex(where: { $0.isSelected }) ?? -1)
        autoSelectIfNeeded()
    }

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
}

/// Bildfläche für VLC 4: wächst beim Drehen mit und meldet Bild-in-Bild an
final class VLCContainerView: UIView, VLCPictureInPictureDrawable {
    weak var model: VLCPlayerModel?

    override func layoutSubviews() {
        super.layoutSubviews()
        for sub in subviews { sub.frame = bounds }
    }

    // VLCPictureInPictureDrawable
    func mediaController() -> (any VLCPictureInPictureMediaControlling)! {
        model?.player
    }

    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)! {
        { [weak self] controller in
            DispatchQueue.main.async {
                guard let model = self?.model else { return }
                model.pipController = controller
                controller?.stateChangeEventHandler = { [weak model] started in
                    DispatchQueue.main.async { model?.isInPictureInPicture = started }
                }
            }
        }
    }

    func canStartPictureInPictureAutomaticallyFromInline() -> Bool { true }
}

/// Die Fläche, auf die VLC das Bild zeichnet
struct VLCVideoSurface: UIViewRepresentable {
    let model: VLCPlayerModel

    func makeUIView(context: Context) -> UIView {
        model.surfaceView
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
    @State private var screenSize: CGSize = UIScreen.main.bounds.size

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
            // Immer DIESELBE Bildfläche – nur die Größe ändert sich.
            // (Ein Neuaufbau beim Drehen ließ VLC ins Leere zeichnen → schwarzes Bild)
            playerArea
                .frame(width: screenSize.width,
                       height: isLandscape ? screenSize.height : screenSize.width * 9 / 16)
                .background(.black)

            if !isLandscape {
                infoList
            }
        }
        // Volle verfügbare Fläche messen (nicht die des Inhalts)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { screenSize = geo.size }
                .onChange(of: geo.size) { _, new in screenSize = new }
        })
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
            if !model.isInPictureInPicture { model.stop() }
            UIApplication.shared.isIdleTimerDisabled = false
            hideTask?.cancel()
            OrientationController.reset()
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

            // Unsichtbare Fläche über dem Bild: Tippen blendet die Bedienung ein/aus
            Color.clear
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
                // Oben: Vollbild links, Ton & Untertitel rechts
                HStack {
                    Button {
                        if isLandscape { OrientationController.exitFullscreen() }
                        else { OrientationController.enterFullscreen() }
                        scheduleHide()
                    } label: {
                        Image(systemName: isLandscape
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.title3)
                            .padding(10)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                    if model.canPictureInPicture {
                        Button { model.togglePictureInPicture(); scheduleHide() } label: {
                            Image(systemName: model.isInPictureInPicture ? "pip.exit" : "pip.enter")
                                .font(.title3)
                                .padding(10)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                    }
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
                Text("Tipp: Bild antippen für die Bedienung. Vollbild über die Taste oben links – klappt auch mit Rotationssperre. Bild-in-Bild: Taste oben rechts oder einfach die App verlassen.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
