import Foundation
import Combine

enum KSAStatus {
    case enabled
    case disabled
    case error
    case unknown
}

/// Keyboard type identifiers per Apple's plist format
enum KeyboardType: Int {
    case ansi = 40  // US/ANSI layout
    case iso = 41   // European/ISO layout
    case jis = 42   // Japanese/JIS layout
}

@MainActor
class KeyboardManager: ObservableObject {
    @Published var status: KSAStatus = .unknown
    @Published var isKSADisabled: Bool = false
    @Published var configuredKeyboards: [String]? = nil
    @Published var lastError: String? = nil

    private let plistPath = "/Library/Preferences/com.apple.keyboardtype.plist"

    // Dependencies
    private let fileSystem: FileSystemProtocol
    private let usbDetector: USBDetectorProtocol.Type
    private let secureExecutor: SecureOperationExecutor

    /// Production initializer using SecureOperationExecutor
    init() {
        self.fileSystem = DefaultFileSystem()
        self.usbDetector = USBKeyboardDetector.self
        self.secureExecutor = SecureOperationExecutor.shared
        refreshStatus()
    }

    /// Test initializer with injectable dependencies
    init(
        fileSystem: FileSystemProtocol,
        usbDetector: USBDetectorProtocol.Type = USBKeyboardDetector.self,
        secureExecutor: SecureOperationExecutor? = nil
    ) {
        self.fileSystem = fileSystem
        self.usbDetector = usbDetector
        self.secureExecutor = secureExecutor ?? SecureOperationExecutor.shared
        refreshStatus()
    }

    func refreshStatus() {
        do {
            if fileSystem.fileExists(atPath: plistPath) {
                if let plistData = fileSystem.contents(atPath: plistPath) {
                    let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
                    if let keyboardTypes = plist?["keyboardtype"] as? [String: Int] {
                        configuredKeyboards = Array(keyboardTypes.keys)
                        isKSADisabled = !keyboardTypes.isEmpty
                        status = keyboardTypes.isEmpty ? .enabled : .disabled
                        lastError = nil
                        return
                    }
                }
            }
            // File doesn't exist or is empty - KSA is enabled
            configuredKeyboards = nil
            isKSADisabled = false
            status = .enabled
            lastError = nil
        } catch {
            status = .error
            lastError = "Failed to read keyboard config: \(error.localizedDescription)"
        }
    }

    func enableKSA() async throws {
        // Remove all keyboard entries via XPC (with Touch ID auth)
        try await secureExecutor.removeAllKeyboardEntries()

        // Wait for filesystem to sync before refreshing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        refreshStatus()
    }

    func disableKSA() async throws {
        // Detect connected keyboards asynchronously
        let keyboards = await detectConnectedKeyboardsAsync()

        // Collect all keyboard entries to add
        var keyboardEntries: [(identifier: String, type: Int)] = []

        if keyboards.isEmpty {
            // Fallback to common Apple keyboard identifiers
            // Format: VendorID-ProductID-0 (e.g., Apple vendor ID 1452)
            keyboardEntries = [
                ("1452-635-0", KeyboardType.ansi.rawValue),   // Apple USB Keyboard
                ("1452-636-0", KeyboardType.ansi.rawValue),   // Apple Wireless Keyboard
                ("0-0-0", KeyboardType.ansi.rawValue)         // Generic fallback
            ]
        } else {
            // Add detected keyboards with correct identifier format
            for keyboard in keyboards {
                // Format: VendorID-ProductID-0 (per Apple's plist structure)
                let identifier = "\(keyboard.vendorID)-\(keyboard.productID)-0"
                keyboardEntries.append((identifier, KeyboardType.ansi.rawValue))
            }
        }

        // Validate all entries first
        for (identifier, type) in keyboardEntries {
            try validateKeyboardEntry(identifier: identifier, type: type)
        }

        // Add keyboard entries via XPC (with Touch ID auth)
        try await secureExecutor.addKeyboardEntries(keyboardEntries)

        // Wait for filesystem to sync before refreshing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        refreshStatus()
    }

    /// Validates keyboard entry format without executing
    private func validateKeyboardEntry(identifier: String, type: Int) throws {
        let components = identifier.split(separator: "-")
        guard components.count == 3,
              components.allSatisfy({ Int($0) != nil }) else {
            throw NSError(domain: "KSAPDismiss", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid keyboard identifier format"])
        }

        guard [40, 41, 42].contains(type) else {
            throw NSError(domain: "KSAPDismiss", code: -4,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid keyboard type (must be 40, 41, or 42)"])
        }
    }

    /// Async wrapper for keyboard detection to avoid blocking main thread
    private func detectConnectedKeyboardsAsync() async -> [(vendorID: Int, productID: Int)] {
        let detector = self.usbDetector
        return await Task.detached(priority: .userInitiated) {
            detector.detectConnectedKeyboards()
        }.value
    }

    // MARK: - Automatic Mode

    /// Auto-configure a newly connected keyboard (for automatic mode)
    /// Called by USBMonitor when a new keyboard is detected.
    func autoConfigureKeyboard(vendorID: Int, productID: Int) async {
        let identifier = "\(vendorID)-\(productID)-0"

        // Check if already configured
        if let configured = configuredKeyboards, configured.contains(identifier) {
            return  // Already configured, skip
        }

        do {
            try validateKeyboardEntry(identifier: identifier, type: KeyboardType.ansi.rawValue)
            // Use XPC directly without Touch ID for auto-mode (silent operation)
            // Note: Helper must already be installed for auto-mode to work
            let xpc = XPCClient.shared
            if !xpc.isConnected {
                try await xpc.connectWithRetry()
            }
            try await xpc.addKeyboardEntries([(identifier, KeyboardType.ansi.rawValue)])

            // Wait and refresh
            try await Task.sleep(nanoseconds: 100_000_000)
            refreshStatus()
        } catch {
            // Silent failure - don't interrupt user
            print("Auto-configure failed for \(identifier): \(error)")
        }
    }
}
