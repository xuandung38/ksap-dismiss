import Foundation
import Sparkle

// MARK: - Notification Names

extension Notification.Name {
    static let startDeferredUpdateCheck = Notification.Name("startDeferredUpdateCheck")
}

/// ViewModel for Sparkle updater integration
@MainActor
final class UpdaterViewModel: ObservableObject {

    private let updaterController: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()
    private let userDriverDelegate = UserDriverDelegate()

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = true
    @Published var downloadProgress: Double = 0.0

    init() {
        // Initialize updater with delegate for beta channels and analytics
        // startingUpdater: false to defer update check (performance optimization)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: userDriverDelegate
        )

        // Bind to updater state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)

        // Listen for deferred update check notification
        NotificationCenter.default.addObserver(
            forName: .startDeferredUpdateCheck,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startUpdater()
            }
        }

        // Listen for download progress updates
        NotificationCenter.default.addObserver(
            forName: .updateDownloadProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let progress = notification.userInfo?["progress"] as? Double {
                    self?.downloadProgress = progress
                }
            }
        }
    }

    /// Start updater with deferred background check
    /// Call this after app launch completes to avoid blocking UI
    func startUpdater() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    /// Trigger manual update check
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    /// Toggle automatic update checks
    func setAutomaticChecks(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    /// Get last update check date
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }
}
