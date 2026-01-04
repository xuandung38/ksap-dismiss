import Foundation
import os.log

/// Combines Touch ID auth with XPC operations
/// Falls back to direct plist writing when SMJobBless helper unavailable
@MainActor
final class SecureOperationExecutor {

    static let shared = SecureOperationExecutor()

    private let touchID = TouchIDAuthenticator.shared
    private let xpc = XPCClient.shared
    private let installer = HelperInstaller.shared
    private let directWriter = DirectPlistWriter.shared
    private let logger = Logger(subsystem: "com.hxd.ksapdismiss", category: "SecureExecutor")

    /// Whether to use fallback mode (no XPC)
    @Published private(set) var useFallbackMode = false

    private init() {}

    // MARK: - Generic Execution

    /// Execute privileged operation with Touch ID
    /// - Parameters:
    ///   - reason: Reason shown to user for biometric prompt
    ///   - operation: The async operation to execute after authentication
    /// - Returns: Result of the operation
    func execute<T>(
        reason: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        logger.info("Starting secure operation: \(reason)")

        // Step 1: Authenticate with Touch ID
        do {
            try await touchID.authenticate(reason: reason)
        } catch let error as TouchIDError where error.shouldFallbackToPassword {
            logger.info("Falling back to password authentication")
            // Fall back to password-based auth
            try await touchID.authenticateWithFallback(reason: reason)
        }

        // Step 2: Ensure helper installed and XPC connected
        if !installer.isInstalled {
            logger.info("Installing helper...")
            try await installer.install()
        }

        if !xpc.isConnected {
            logger.info("Establishing XPC connection")
            try await xpc.connectWithRetry()
        }

        // Step 3: Execute operation
        logger.info("Executing privileged operation")
        return try await operation()
    }

    // MARK: - Keyboard Operations

    /// Add keyboard entries with Touch ID authentication
    /// - Parameter entries: Keyboard entries to add
    func addKeyboardEntries(_ entries: [(identifier: String, type: Int)]) async throws {
        // Try XPC first, fall back to direct write
        do {
            try await execute(reason: "Configure keyboard settings") {
                try await self.xpc.addKeyboardEntries(entries)
            }
            logger.info("Added \(entries.count) keyboard entries via XPC")
        } catch let error as HelperInstallerError {
            // SMJobBless failed - use fallback
            logger.warning("XPC failed (\(error.localizedDescription)), using fallback")
            useFallbackMode = true
            try await directWriter.addKeyboardEntries(entries)
            logger.info("Added \(entries.count) keyboard entries via fallback")
        } catch let error as XPCError {
            // XPC connection failed - use fallback
            logger.warning("XPC error (\(error.localizedDescription)), using fallback")
            useFallbackMode = true
            try await directWriter.addKeyboardEntries(entries)
            logger.info("Added \(entries.count) keyboard entries via fallback")
        }
    }

    /// Remove all keyboard entries with Touch ID authentication
    func removeAllKeyboardEntries() async throws {
        // Try XPC first, fall back to direct write
        do {
            try await execute(reason: "Reset keyboard settings") {
                try await self.xpc.removeAllKeyboardEntries()
            }
            logger.info("Removed all keyboard entries via XPC")
        } catch let error as HelperInstallerError {
            // SMJobBless failed - use fallback
            logger.warning("XPC failed (\(error.localizedDescription)), using fallback")
            useFallbackMode = true
            try await directWriter.removeAllKeyboardEntries()
            logger.info("Removed all keyboard entries via fallback")
        } catch let error as XPCError {
            // XPC connection failed - use fallback
            logger.warning("XPC error (\(error.localizedDescription)), using fallback")
            useFallbackMode = true
            try await directWriter.removeAllKeyboardEntries()
            logger.info("Removed all keyboard entries via fallback")
        }
    }

    /// Get keyboard status (no auth required - read-only)
    func getKeyboardStatus() async throws -> (hasEntries: Bool, keyboards: [String]?) {
        // Ensure helper installed and connected but no auth for read
        if !installer.isInstalled {
            try await installer.install()
        }
        if !xpc.isConnected {
            try await xpc.connectWithRetry()
        }
        return try await xpc.getKeyboardStatus()
    }

    // MARK: - Helper Management

    /// Check if helper is installed
    var isHelperInstalled: Bool {
        installer.isInstalled
    }

    /// Install helper explicitly
    func installHelper() async throws {
        try await installer.install()
    }
}
