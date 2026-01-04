import Foundation
import ServiceManagement
import Security
import os.log

/// Handles privileged helper installation via SMJobBless
@MainActor
final class HelperInstaller: ObservableObject {

    static let shared = HelperInstaller()

    @Published private(set) var isInstalled = false
    @Published private(set) var installedVersion: String?
    @Published private(set) var isInstalling = false

    private let helperBundleID = kHelperBundleID
    private let helperPath = "/Library/PrivilegedHelperTools/\(kHelperBundleID)"
    private let logger = Logger(subsystem: "com.hxd.ksapdismiss", category: "HelperInstaller")

    private init() {
        checkInstallationStatus()
    }

    // MARK: - Installation Status

    /// Check if helper is installed
    func checkInstallationStatus() {
        isInstalled = FileManager.default.fileExists(atPath: helperPath)
        if isInstalled {
            installedVersion = getInstalledVersion()
            logger.info("Helper installed: v\(self.installedVersion ?? "unknown")")
        } else {
            installedVersion = nil
            logger.info("Helper not installed")
        }
    }

    /// Get version of installed helper
    private func getInstalledVersion() -> String? {
        // Read version from helper's Info.plist embedded in binary
        // For now, attempt XPC version check
        return nil
    }

    /// Check if update is needed
    var needsUpdate: Bool {
        guard isInstalled, let installed = installedVersion else {
            return !isInstalled
        }
        return installed != kHelperVersion
    }

    // MARK: - Installation

    /// Install or update the helper
    func install() async throws {
        guard !isInstalling else {
            throw HelperInstallerError.alreadyInstalling
        }

        isInstalling = true
        defer { isInstalling = false }

        logger.info("Starting helper installation...")

        // Create authorization reference
        var authRef: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errAuthorizationSuccess, let auth = authRef else {
            logger.error("Failed to create authorization: \(status)")
            throw HelperInstallerError.authorizationFailed
        }

        defer { AuthorizationFree(auth, []) }

        // Request authorization with user interaction
        var item = kSMRightBlessPrivilegedHelper.withCString { cString in
            AuthorizationItem(
                name: cString,
                valueLength: 0,
                value: nil,
                flags: 0
            )
        }

        var rights = withUnsafeMutablePointer(to: &item) { itemPtr in
            AuthorizationRights(count: 1, items: itemPtr)
        }

        status = AuthorizationCopyRights(
            auth,
            &rights,
            nil,
            [.interactionAllowed, .extendRights, .preAuthorize],
            nil
        )

        guard status == errAuthorizationSuccess else {
            if status == errAuthorizationCanceled {
                logger.info("User canceled authorization")
                throw HelperInstallerError.userCanceled
            }
            logger.error("Authorization failed: \(status)")
            throw HelperInstallerError.authorizationDenied
        }

        // Bless the helper
        var cfError: Unmanaged<CFError>?

        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            helperBundleID as CFString,
            auth,
            &cfError
        )

        if success {
            logger.info("Helper installed successfully")
            checkInstallationStatus()
        } else {
            let error = cfError?.takeRetainedValue()
            let description = error.map { CFErrorCopyDescription($0) as String? } ?? nil
            logger.error("SMJobBless failed: \(description ?? "unknown")")
            throw HelperInstallerError.blessFailed(description)
        }
    }

    /// Uninstall the helper
    func uninstall() async throws {
        guard isInstalled else { return }

        logger.info("Uninstalling helper...")

        // Remove helper binary
        do {
            try FileManager.default.removeItem(atPath: helperPath)
        } catch {
            logger.error("Failed to remove helper: \(error.localizedDescription)")
            throw HelperInstallerError.uninstallFailed(error.localizedDescription)
        }

        // Remove launchd plist
        let plistPath = "/Library/LaunchDaemons/\(helperBundleID).plist"
        if FileManager.default.fileExists(atPath: plistPath) {
            do {
                try FileManager.default.removeItem(atPath: plistPath)
            } catch {
                logger.warning("Failed to remove launchd plist: \(error.localizedDescription)")
            }
        }

        checkInstallationStatus()
        logger.info("Helper uninstalled")
    }

    // MARK: - Convenience

    /// Install if needed, return true if installation occurred
    func installIfNeeded() async throws -> Bool {
        if isInstalled && !needsUpdate {
            return false
        }
        try await install()
        return true
    }
}

// MARK: - Errors

enum HelperInstallerError: LocalizedError {
    case alreadyInstalling
    case authorizationFailed
    case authorizationDenied
    case userCanceled
    case blessFailed(String?)
    case uninstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInstalling:
            return "Installation already in progress"
        case .authorizationFailed:
            return "Failed to create authorization"
        case .authorizationDenied:
            return "Authorization denied. Administrator access required."
        case .userCanceled:
            return "Installation canceled"
        case .blessFailed(let msg):
            return "Helper installation failed: \(msg ?? "unknown error")"
        case .uninstallFailed(let msg):
            return "Helper uninstall failed: \(msg)"
        }
    }
}
