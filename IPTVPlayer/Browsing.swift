import SwiftUI

/// Jahreszahl aus Text holen, z. B. „Mob Land 2023“ oder „2019-05-01“
nonisolated enum YearParser {
    static func year(in text: String) -> Int? {
        let current = Calendar.current.component(.year, from: Date()) + 1
        var found: Int?
        var digits = ""
        for ch in text + " " {
            if ch.isASCII, ch.isNumber {
                digits.append(ch)
            } else {
                if digits.count == 4, let y = Int(digits), (1900...current).contains(y) { found = y }
                digits = ""
            }
        }
        return found
    }
}

/// Sortierung für Filme, Serien (und Live-TV)
enum SortOrder: String, CaseIterable, Identifiable {
    case provider, recent, alphabet, random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: "Wie beim Anbieter"
        case .recent: "Zuletzt hinzugefügt"
        case .alphabet: "Alphabetisch (A–Z)"
        case .random: "Zufällig"
        }
    }

    var icon: String {
        switch self {
        case .provider: "list.number"
        case .recent: "clock"
        case .alphabet: "textformat"
        case .random: "shuffle"
        }
    }

    func apply<T>(_ items: [T], seed: Int, id: (T) -> String, name: (T) -> String, date: (T) -> Date?) -> [T] {
        switch self {
        case .provider:
            return items
        case .recent:
            // Ohne Datum ans Ende, sonst neueste zuerst
            return items.enumerated().sorted { a, b in
                switch (date(a.element), date(b.element)) {
                case let (x?, y?): return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.offset < b.offset
                }
            }.map(\.element)
        case .alphabet:
            return items.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        case .random:
            return items.sorted { Self.shuffleKey(id($0), seed) < Self.shuffleKey(id($1), seed) }
        }
    }

    private static func shuffleKey(_ id: String, _ seed: Int) -> Int {
        var h = Hasher()
        h.combine(seed)
        h.combine(id)
        return h.finalize()
    }
}

// MARK: - Zufalls-Vorschlag

struct RandomCandidate: Identifiable, Hashable {
    let id: String
    let title: String
    let group: String
    let imageURL: URL?
    let year: Int?
    let rating: Double?
}

enum DecadeFilter: String, CaseIterable, Identifiable {
    case all, y2020, y2010, y2000, y1990, older
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Alle Jahre"
        case .y2020: "Ab 2020"
        case .y2010: "2010–2019"
        case .y2000: "2000–2009"
        case .y1990: "1990–1999"
        case .older: "Vor 1990"
        }
    }
    func matches(_ year: Int?) -> Bool {
        guard self != .all else { return true }
        guard let y = year else { return false }
        switch self {
        case .all: return true
        case .y2020: return y >= 2020
        case .y2010: return (2010...2019).contains(y)
        case .y2000: return (2000...2009).contains(y)
        case .y1990: return (1990...1999).contains(y)
        case .older: return y < 1990
        }
    }
}

/// „Was schau ich heute?“ – schlägt zufällig etwas vor, mit Filtern
struct RandomPickView: View {
    let title: String
    let candidates: [RandomCandidate]
    let groups: [String]
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("random.group") private var group = ""
    @AppStorage("random.decade") private var decade: DecadeFilter = .all
    @AppStorage("random.minRating") private var minRating = 0.0
    @State private var current: RandomCandidate?
    @State private var lastIDs: [String] = []

    private var hasRatings: Bool { candidates.contains { ($0.rating ?? 0) > 0 } }
    private var hasYears: Bool { candidates.contains { $0.year != nil } }

    private var pool: [RandomCandidate] {
        candidates.filter { c in
            (group.isEmpty || c.group == group)
            && decade.matches(c.year)
            && (minRating == 0 || (c.rating ?? 0) >= minRating)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let c = current {
                        HStack(alignment: .top, spacing: 14) {
                            AsyncImage(url: c.imageURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
                            }
                            .frame(width: 110, height: 160)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(c.title).font(.headline)
                                if let y = c.year { Label(String(y), systemImage: "calendar").font(.subheadline) }
                                if let r = c.rating, r > 0 {
                                    Label(String(format: "%.1f", r), systemImage: "star.fill")
                                        .font(.subheadline).foregroundStyle(.yellow)
                                }
                                Text(c.group).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        ContentUnavailableView("Nichts gefunden", systemImage: "dice",
                                               description: Text("Mit diesen Filtern gibt es keine Treffer."))
                    }
                }

                Section {
                    Button {
                        roll()
                    } label: {
                        Label("Nochmal würfeln", systemImage: "dice")
                    }
                    Button {
                        guard let c = current else { return }
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onPick(c.id) }
                    } label: {
                        Label("Ansehen", systemImage: "play.fill").bold()
                    }
                    .disabled(current == nil)
                }

                Section("Filter") {
                    Picker("Kategorie", selection: $group) {
                        Text("Alle Kategorien").tag("")
                        ForEach(groups, id: \.self) { Text($0).tag($0) }
                    }
                    if hasYears {
                        Picker("Erscheinungsjahr", selection: $decade) {
                            ForEach(DecadeFilter.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if hasRatings {
                        Picker("Bewertung", selection: $minRating) {
                            Text("Egal").tag(0.0)
                            Text("ab 6").tag(6.0)
                            Text("ab 7").tag(7.0)
                            Text("ab 8").tag(8.0)
                        }
                    }
                    Text("\(pool.count) Treffer").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
            .onAppear { if !groups.contains(group) { group = "" }; roll() }
            .onChange(of: group) { _, _ in roll() }
            .onChange(of: decade) { _, _ in roll() }
            .onChange(of: minRating) { _, _ in roll() }
        }
    }

    /// Zufällig wählen, möglichst nicht dasselbe wie die letzten Male
    private func roll() {
        let options = pool
        guard !options.isEmpty else { current = nil; return }
        let fresh = options.filter { !lastIDs.contains($0.id) }
        let pick = (fresh.isEmpty ? options : fresh).randomElement()
        current = pick
        if let id = pick?.id {
            lastIDs.append(id)
            if lastIDs.count > 10 { lastIDs.removeFirst() }
        }
    }
}

/// Würfel-Knopf für die Werkzeugleiste
struct RandomButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "dice") }
            .accessibilityLabel("Zufälliger Vorschlag")
    }
}
