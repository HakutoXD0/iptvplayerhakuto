import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: PlaylistStore
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable { case xtream = "Xtream Codes", m3u = "M3U" }

    @State private var mode: Mode = .xtream
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var m3uURL = ""
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quelle", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch mode {
                case .xtream:
                    Section {
                        TextField("Server, z. B. http://example.com:8080", text: $server)
                            .keyboardType(.URL)
                        TextField("Benutzername", text: $username)
                        SecureField("Passwort", text: $password)
                        Button("Verbinden") {
                            connect(.xtream(XtreamAccount(server: server, username: username, password: password)))
                        }
                        .disabled(server.isEmpty || username.isEmpty || password.isEmpty || store.isLoading)
                    } header: {
                        Text("Xtream-Login")
                    } footer: {
                        Text("Die Zugangsdaten bekommst du von deinem Anbieter. Sie werden im Schlüsselbund gespeichert.")
                    }

                case .m3u:
                    Section("Playlist-URL") {
                        TextField("https://…/playlist.m3u", text: $m3uURL)
                            .keyboardType(.URL)
                        Button("Laden") { connect(.m3u(m3uURL)) }
                            .disabled(m3uURL.isEmpty || store.isLoading)
                    }
                    Section {
                        Button("M3U-Datei aus „Dateien“ importieren …") { showImporter = true }
                    }
                }

                if store.isLoading {
                    Section { ProgressView("Verbinde …").frame(maxWidth: .infinity) }
                }
                if let error = store.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if let info = store.userInfo {
                    Section("Konto") {
                        LabeledContent("Status", value: info.status ?? "–")
                        if let exp = info.expDate {
                            LabeledContent("Läuft ab", value: exp.formatted(date: .abbreviated, time: .omitted))
                        }
                        if let max = info.maxConnections {
                            LabeledContent("Max. Verbindungen", value: max)
                        }
                    }
                }

                if store.source != nil {
                    Section {
                        Button("Abmelden / Playlist entfernen", role: .destructive) { store.disconnect() }
                    }
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onAppear(perform: prefill)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .text, .plainText]) { result in
                guard case .success(let url) = result else { return }
                Task { if await store.importM3UFile(url) { dismiss() } }
            }
        }
    }

    private func connect(_ source: PlaylistSource) {
        Task { if await store.connect(source) { dismiss() } }
    }

    private func prefill() {
        switch store.source {
        case .xtream(let a):
            mode = .xtream; server = a.server; username = a.username; password = a.password
        case .m3u(let url):
            mode = .m3u; m3uURL = url.hasPrefix("file:") ? "" : url
        case nil:
            break
        }
    }
}
