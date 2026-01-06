import Foundation
import Sparkle

// MARK: - Notification Names

extension Notification.Name {
    static let updateDownloadProgress = Notification.Name("updateDownloadProgress")
}

/// Delegate for handling Sparkle UI interactions and progress tracking
@MainActor
final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {

    // MARK: - Download Progress Tracking

    func standardUserDriver(
        _ userDriver: SPUStandardUserDriver,
        didReceiveUpdateDownloadData bytesDownloaded: UInt64,
        expectedContentLength: UInt64
    ) {
        let progress = Double(bytesDownloaded) / Double(expectedContentLength)

        // Post notification for UI updates (e.g., menu bar progress indicator)
        NotificationCenter.default.post(
            name: .updateDownloadProgress,
            object: nil,
            userInfo: ["progress": progress]
        )
    }
}
