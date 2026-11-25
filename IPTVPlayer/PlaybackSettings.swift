import Foundation
import CoreGraphics

/// Bevorzugte Sprache für Tonspur bzw. Untertitel
enum PreferredLanguage: String, CaseIterable, Identifiable {
    case none, de, en, fr, es, it, tr, pl, bks, ru, ar

    var id: String { rawValue }

    /// Anzeige im Ton-Menü (.none = Standardspur der Datei)
    var audioTitle: String { self == .none ? "Standard der Datei" : title }
    /// Anzeige im Untertitel-Menü (.none = aus)
    var subtitleTitle: String { self == .none ? "Aus" : title }

    var title: String {
        switch self {
        case .none: "–"
        case .de: "Deutsch"
        case .en: "Englisch"
        case .fr: "Französisch"
        case .es: "Spanisch"
        case .it: "Italienisch"
        case .tr: "Türkisch"
        case .pl: "Polnisch"
        case .bks: "Bosnisch/Kroatisch/Serbisch"
        case .ru: "Russisch"
        case .ar: "Arabisch"
        }
    }

    /// Sprachcodes für VLC (:audio-language / :sub-language)
    var vlcCodes: String {
        switch self {
        case .none: ""
        case .de: "de,deu,ger"
        case .en: "en,eng"
        case .fr: "fr,fra,fre"
        case .es: "es,spa"
        case .it: "it,ita"
        case .tr: "tr,tur"
        case .pl: "pl,pol"
        case .bks: "hr,hrv,scr,sr,srp,scc,bs,bos"
        case .ru: "ru,rus"
        case .ar: "ar,ara"
        }
    }

    /// Wörter, an denen eine Spur im Namen erkannt wird (z. B. "Track 2 - [German]")
    var keywords: Set<String> {
        let codes = vlcCodes.split(separator: ",").map(String.init)
        let names: [String]
        switch self {
        case .none: names = []
        case .de: names = ["german", "deutsch", "germany"]
        case .en: names = ["english", "englisch"]
        case .fr: names = ["french", "français", "francais", "französisch"]
        case .es: names = ["spanish", "español", "espanol", "castellano", "latino"]
        case .it: names = ["italian", "italiano"]
        case .tr: names = ["turkish", "türkçe", "turkce"]
        case .pl: names = ["polish", "polski"]
        case .bks: names = ["croatian", "serbian", "bosnian", "hrvatski", "srpski", "bosanski"]
        case .ru: names = ["russian", "русский"]
        case .ar: names = ["arabic", "العربية"]
        }
        return Set(codes + names)
    }

    /// Passt ein Spurname zu dieser Sprache?
    func matches(_ trackName: String) -> Bool {
        guard self != .none else { return false }
        let tokens = trackName.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        return tokens.contains(where: keywords.contains)
    }
}

/// Maximale Qualität für Live-TV (wirkt nur, wenn der Sender mehrere Stufen anbietet)
enum LiveQuality: String, CaseIterable, Identifiable {
    case auto, p1080, p720, p480

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Automatisch"
        case .p1080: "Max. 1080p"
        case .p720: "Max. 720p"
        case .p480: "Max. 480p (spart Daten)"
        }
    }

    /// .zero = keine Begrenzung
    var maxResolution: CGSize {
        switch self {
        case .auto: .zero
        case .p1080: CGSize(width: 1920, height: 1080)
        case .p720: CGSize(width: 1280, height: 720)
        case .p480: CGSize(width: 854, height: 480)
        }
    }
}

/// Schlüssel für @AppStorage
enum SettingsKey {
    static let audioLanguage = "prefAudioLanguage"
    static let subtitleLanguage = "prefSubtitleLanguage"
    static let liveQuality = "liveMaxQuality"
    static let liveUseVLC = "liveUseVLC"
}
