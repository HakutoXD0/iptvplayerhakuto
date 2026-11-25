import Foundation
import UIKit

nonisolated struct DownloadItem: Codable, Identifiable, Hashable, Sendable {
    enum State: String, Codable, Sendable { case downloading, finished, failed }

    let id: String          // = Channel.id
    let name: String
    let group: String
    let logoURL: URL?
    let remoteURL: URL
    let kind: Channel.Kind
    let fileName: String
    var state: State

    var asChannel: Channel {
        Channel(id: id, name: name, group: group, logoURL: logoURL, streamURL: remoteURL, kind: kind)
    }
}

nonisolated enum DownloadPaths {
    static var folder: URL {
        var url = URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            // Große Videos nicht ins iCloud-Backup
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return url
    }
    static var index: URL { URL.documentsDirectory.appending(path: "downloads.json") }
    static func file(_ name: String) -> URL { folder.appending(path: name) }
}

/// Filme & Serienfolgen herunterladen – läuft auch weiter, wenn die App im Hintergrund ist
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var progress: [String: Double] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.background(withIdentifier: "iptvplayer.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: DownloadDelegate(), delegateQueue: nil)

        if let data = try? Data(contentsOf: DownloadPaths.index),
           let saved = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            items = saved
        }
        // Downloads, die nach einem App-Neustart keinen laufenden Task mehr haben → fehlgeschlagen
        session.getAllTasks { tasks in
            let running = Set(tasks.compactMap { DownloadDelegate.parse($0.taskDescription)?.id })
            Task { @MainActor in DownloadManager.shared.reconcile(running: running) }
        }
    }

    // MARK: Abfragen

    func item(for channel: Channel) -> DownloadItem? { items.first { $0.id == channel.id } }

    /// Lokale Datei, falls fertig heruntergeladen
    func localFileURL(for channel: Channel) -> URL? {
        guard let item = item(for: channel), item.state == .finished else { return nil }
        let url = DownloadPaths.file(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var usedBytes: Int64 {
        items.filter { $0.state == .finished }.reduce(0) { sum, item in
            let size = (try? DownloadPaths.file(item.fileName).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    // MARK: Aktionen

    func start(_ channel: Channel) {
        guard channel.kind != .live else { return }
        if let existing = item(for: channel), existing.state != .failed { return }
        items.removeAll { $0.id == channel.id }

        let ext = channel.streamURL.pathExtension.isEmpty ? "mp4" : channel.streamURL.pathExtension
        let safeID = channel.id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let fileName = "\(safeID).\(ext)"

        let task = session.downloadTask(with: channel.streamURL)
        task.taskDescription = "\(channel.id)|\(fileName)"
        items.insert(DownloadItem(id: channel.id, name: channel.name, group: channel.group,
                                  logoURL: channel.logoURL, remoteURL: channel.streamURL,
                                  kind: channel.kind, fileName: fileName, state: .downloading), at: 0)
        progress[channel.id] = 0
        save()
        task.resume()
    }

    func delete(_ item: DownloadItem) {
        let id = item.id
        session.getAllTasks { tasks in
            tasks.filter { DownloadDelegate.parse($0.taskDescription)?.id == id }.forEach { $0.cancel() }
        }
        try? FileManager.default.removeItem(at: DownloadPaths.file(item.fileName))
        items.removeAll { $0.id == id }
        progress[id] = nil
        save()
    }

    // MARK: Rückmeldungen vom Delegate

    func update(id: String, progress p: Double) {
        // Nur in 1-%-Schritten aktualisieren, sonst ruckelt die Liste
        if abs((progress[id] ?? 0) - p) >= 0.01 || p >= 1 { progress[id] = p }
    }

    func finished(id: String) { setState(.finished, for: id) }
    func failed(id: String) { setState(.failed, for: id) }

    private func setState(_ state: DownloadItem.State, for id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = state
        progress[id] = nil
        save()
    }

    private func reconcile(running: Set<String>) {
        var changed = false
        for i in items.indices where items[i].state == .downloading && !running.contains(items[i].id) {
            items[i].state = .failed
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: DownloadPaths.index) }
    }
}

nonisolated final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {

    static func parse(_ description: String?) -> (id: String, fileName: String)? {
        guard let parts = description?.split(separator: "|", maxSplits: 1), parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let info = Self.parse(downloadTask.taskDescription) else { return }
        let id = info.id
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            Task { @MainActor in DownloadManager.shared.failed(id: id) }
            return
        }
        // Datei muss sofort verschoben werden, iOS löscht sie nach dieser Methode
        let dest = DownloadPaths.file(info.fileName)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            Task { @MainActor in DownloadManager.shared.finished(id: id) }
        } catch {
            Task { @MainActor in DownloadManager.shared.failed(id: id) }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let id = Self.parse(downloadTask.taskDescription)?.id else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in DownloadManager.shared.update(id: id, progress: p) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = Self.parse(task.taskDescription)?.id else { return }
        if (error as? URLError)?.code == .cancelled { return }
        Task { @MainActor in DownloadManager.shared.failed(id: id) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            DownloadManager.shared.backgroundCompletionHandler?()
            DownloadManager.shared.backgroundCompletionHandler = nil
        }
    }
}

/// Weckt die App, wenn Hintergrund-Downloads fertig werden
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Erlaubt der Vollbild-Taste, Querformat zu erzwingen (auch mit Rotationssperre)
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationController.mask
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}
