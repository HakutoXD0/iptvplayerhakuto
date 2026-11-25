import UIKit

/// Vollbild per Taste: dreht die App ins Querformat – unabhängig von der Rotationssperre
@MainActor
enum OrientationController {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    static func enterFullscreen() {
        apply(mask: .landscape, orientation: .landscapeRight)
    }

    static func exitFullscreen() {
        apply(mask: .portrait, orientation: .portrait)
        // Danach wieder normales Drehen erlauben
        Task {
            try? await Task.sleep(for: .seconds(1))
            mask = .allButUpsideDown
            refresh()
        }
    }

    /// Beim Verlassen des Players aufräumen
    static func reset() {
        if mask == .landscape { exitFullscreen() }
    }

    private static func apply(mask newMask: UIInterfaceOrientationMask, orientation: UIInterfaceOrientationMask) {
        mask = newMask
        refresh()
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        }
    }

    private static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}
