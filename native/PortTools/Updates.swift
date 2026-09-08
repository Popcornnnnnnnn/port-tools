import AppKit
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdaterBridge: ObservableObject {
    static let shared = UpdaterBridge()
#if canImport(Sparkle)
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
#endif

    func checkForUpdates() {
#if canImport(Sparkle)
        controller.checkForUpdates(nil)
#else
        NSWorkspace.shared.open(URL(string: "https://github.com/Popcornnnnnnnn/port-tools/releases/latest")!)
#endif
    }
}
