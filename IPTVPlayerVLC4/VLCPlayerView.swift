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
    var pipWindow: AnyObject? {
        didSet { canPictureInPicture = pipWindow != nil }
    }

    @Published var resumedAt: String?

    private let channel: Channel
    private var resumeMs: Double = 0
    private var lastSavedMs: Double = 0
    private let prefAudio: PreferredLanguage
    private let prefSubtitle: PreferredLanguage
    private var didAutoSelect = false
    private var isSeeking = false

    init(url: URL, channel: Channel, prefAudio: PreferredLanguage, prefSubtitle: PreferredLanguage) {
        self.channel = channel
        if let start = WatchHistory.shared.resumePosition(for: channel) { resumeMs = start * 1000 }
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

    /// Seitenverhältnis des Videos (Fallback 16:9, solange VLC es noch nicht kennt)
    var videoAspect: CGFloat {
        let size: CGSize = player.videoSize
        return size.width > 0 && size.height > 0 ? size.width / size.height : 16 / 9
    }

    // MARK: Verlauf

    private func currentMs() -> Double {
        let t: VLCTime? = player.time
        return Double(t?.intValue ?? 0)
    }

    private func lengthMs() -> Double {
        let l: VLCTime? = player.media?.length
        return Double(l?.intValue ?? 0)
    }

    /// Bei Filmen/Folgen: an der gemerkten Stelle starten, dann alle 5 s speichern
    private func handleHistory() {
        guard channel.kind != .live else { return }
        let length = lengthMs()
        guard length > 0 else { return }
        if resumeMs > 0 {
            player.position = .init(resumeMs / length)
            let total = Int(resumeMs / 1000)
            resumedAt = String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            resumeMs = 0
            return
        }
        let now = currentMs()
        if abs(now - lastSavedMs) >= 5000 {
            lastSavedMs = now
            WatchHistory.shared.update(channel: channel, position: now / 1000, duration: length / 1000)
        }
    }

    func saveProgress() {
        guard channel.kind != .live else { return }
        let length = lengthMs(), now = currentMs()
        guard length > 0, now > 0 else { return }
        WatchHistory.shared.update(channel: channel, position: now / 1000, duration: length / 1000)
    }

    func restartFromBeginning() {
        player.position = 0
        resumedAt = nil
    }

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
        guard let pip = pipWindow else { return }
        let sel = NSSelectorFromString(isInPictureInPicture ? "stopPictureInPicture" : "startPictureInPicture")
        if pip.responds(to: sel) { _ = pip.perform(sel) }
        // Falls VLC den Status nicht meldet: selbst umschalten
        isInPictureInPicture.toggle()
    }

    private func invalidatePiP() {
        let sel = NSSelectorFromString("invalidatePlaybackState")
        if let pip = pipWindow, pip.responds(to: sel) { _ = pip.perform(sel) }
    }

    func jump(milliseconds: Int64) {
        let length = lengthMs()
        guard length > 0 else { return }
        let target = min(max(currentMs() + Double(milliseconds), 0), length)
        player.position = .init(target / length)
    }

    var lengthMsPublic: Double { lengthMs() }
    var timeMsPublic: Double { currentMs() }

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
        invalidatePiP()
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
        handleHistory()
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

/// Bildfläche für VLC 4: wächst beim Drehen mit und meldet Bild-in-Bild an.
/// Die Bild-in-Bild-Schnittstellen von VLCKit 4 (Vorabversion) ändern sich noch oft –
/// daher werden sie hier über die Objective-C-Laufzeit angebunden statt über feste Swift-Namen.
final class VLCContainerView: UIView {
    weak var model: VLCPlayerModel? {
        didSet { pipAdapter.model = model }
    }
    private let pipAdapter = PiPMediaAdapter()

    private static let registerProtocol: Void = {
        if let proto = NSProtocolFromString("VLCPictureInPictureDrawable") {
            class_addProtocol(VLCContainerView.self, proto)
        }
        if let proto = NSProtocolFromString("VLCPictureInPictureMediaControlling") {
            class_addProtocol(PiPMediaAdapter.self, proto)
        }
    }()

    override init(frame: CGRect) {
        _ = Self.registerProtocol
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        for sub in subviews { sub.frame = bounds }
    }

    // MARK: VLCPictureInPictureDrawable (per Laufzeit)

    @objc func mediaController() -> AnyObject { pipAdapter }

    @objc func pictureInPictureReady() -> (@convention(block) (AnyObject?) -> Void) {
        return { [weak self] controller in
            DispatchQueue.main.async {
                guard let model = self?.model, let controller else { return }
                model.pipWindow = controller
                let setter = NSSelectorFromString("setStateChangeEventHandler:")
                if controller.responds(to: setter) {
                    let handler: @convention(block) (Bool) -> Void = { [weak model] started in
                        DispatchQueue.main.async { model?.isInPictureInPicture = started }
                    }
                    _ = controller.perform(setter, with: handler as AnyObject)
                }
            }
        }
    }

    @objc func canStartPictureInPictureAutomaticallyFromInline() -> Bool { true }
}

/// Liefert dem Bild-in-Bild-Fenster Infos und nimmt Play/Pause/Spulen entgegen
final class PiPMediaAdapter: NSObject {
    weak var model: VLCPlayerModel?

    @objc func play() { model?.player.play() }
    @objc func pause() { model?.player.pause() }

    @objc(seekBy:completion:) func seekBy(_ offset: Int64, completion: (@convention(block) () -> Void)?) {
        model?.jump(milliseconds: offset)
        if let completion { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion() } }
    }

    @objc(seekBy:) func seekBy(_ offset: Int64) { model?.jump(milliseconds: offset) }

    @objc func mediaLength() -> Int64 { Int64(model?.lengthMsPublic ?? 0) }
    @objc func mediaTime() -> Int64 { Int64(model?.timeMsPublic ?? 0) }
    @objc func isMediaSeekable() -> Bool { (model?.lengthMsPublic ?? 0) > 0 }
    @objc func isMediaPlaying() -> Bool { model?.player.isPlaying ?? false }
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
    @AppStorage("videoFill") private var videoFill = false
    @State private var fillHint: String?

    init(channel: Channel) {
        self.channel = channel
        let defaults = UserDefaults.standard
        let audio = PreferredLanguage(rawValue: defaults.string(forKey: SettingsKey.audioLanguage) ?? "") ?? .de
        let subs = PreferredLanguage(rawValue: defaults.string(forKey: SettingsKey.subtitleLanguage) ?? "") ?? .none
        let url = DownloadManager.shared.localFileURL(for: channel) ?? channel.streamURL
        _model = StateObject(wrappedValue: VLCPlayerModel(url: url, channel: channel, prefAudio: audio, prefSubtitle: subs))
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isLive: Bool { channel.kind == .live }

    var body: some View {
        // Größe kommt vom verfügbaren Platz (nicht vom Inhalt) – so bleibt nach dem Drehen nichts hängen
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Immer DIESELBE Bildfläche – nur die Größe ändert sich
                playerArea
                    .frame(width: geo.size.width,
                           height: isLandscape ? geo.size.height : geo.size.width * 9 / 16)
                    .clipped()
                    .background(.black)

                if !isLandscape {
                    infoList
                }
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
            model.saveProgress()
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
        GeometryReader { geo in
        ZStack {
            VLCVideoSurface(model: model)
                .scaleEffect(videoFill ? fillScale(in: geo.size) : 1)
                .animation(.easeInOut(duration: 0.25), value: videoFill)

            // Unsichtbare Fläche über dem Bild:
            // 1× Tippen = Bedienung ein/aus, 2× Tippen = Ganzes Bild ⇄ Bildschirm füllen
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleFill() }
                .onTapGesture { toggleControls() }

            if let hint = fillHint {
                Text(hint)
                    .font(.footnote.bold())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if model.isBuffering && model.errorText == nil {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if showControls {
                controls
                    .transition(.opacity)
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .animation(.easeInOut(duration: 0.2), value: fillHint)
        }
    }

    /// Vergrößerung, damit das Video die ganze Fläche ausfüllt (Ränder werden abgeschnitten)
    private func fillScale(in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let ar = model.videoAspect
        let fitWidth = min(size.width, size.height * ar)
        let fitHeight = fitWidth / ar
        return max(size.width / fitWidth, size.height / fitHeight)
    }

    private func toggleFill() {
        videoFill.toggle()
        fillHint = videoFill ? "Bildschirm füllen" : "Ganzes Bild"
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            fillHint = nil
        }
    }

    private var controls: some View {
        ZStack {
            Color.black.opacity(0.35)
                .onTapGesture(count: 2) { toggleFill() }
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
                .padding(.horizontal, isLandscape ? 56 : 12)
                .padding(.top, isLandscape ? 20 : 8)

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
                    .padding(.horizontal, isLandscape ? 56 : 16)
                    .padding(.bottom, isLandscape ? 24 : 8)
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

            if let resumed = model.resumedAt {
                Section {
                    HStack {
                        Label("Fortgesetzt bei \(resumed)", systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                        Spacer()
                        Button("Von vorn") { model.restartFromBeginning() }
                            .buttonStyle(.bordered)
                            .font(.footnote)
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
                Text("Tipp: Bild antippen für die Bedienung, doppelt tippen zum Füllen/Ganzes Bild. Vollbild über die Taste oben links – klappt auch mit Rotationssperre. Bild-in-Bild: Taste oben rechts oder einfach die App verlassen.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
