import Foundation
import Security
import os.log

/// Direct plist writer using Authorization Services
/// Fallback when SMJobBless helper isn't available (unsigned builds)
@MainActor
final class DirectPlistWriter {

    static let shared = DirectPlistWriter()

    private let plistPath = "/Library/Preferences/com.apple.keyboardtype.plist"
    private let logger = Logger(subsystem: "com.hxd.ksapdismiss", category: "DirectPlistWriter")

    private init() {}

    /// Add keyboard entries to the plist
    func addKeyboardEntries(_ entries: [(identifier: String, type: Int)]) async throws {
        logger.info("Adding \(entries.count) keyboard entries via direct write")

        // Build plist content
        var keyboardTypes: [String: Int] = [:]

        // Read existing entries first
        if FileManager.default.fileExists(atPath: plistPath),
           let data = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let existing = plist["keyboardtype"] as? [String: Int] {
            keyboardTypes = existing
        }

        // Add new entries
        for (identifier, type) in entries {
            keyboardTypes[identifier] = type
        }

        let plistContent: [String: Any] = ["keyboardtype": keyboardTypes]

        try await writePlist(plistContent)
        logger.info("Successfully added keyboard entries")
    }

    /// Remove all keyboard entries (enable KSA)
    func removeAllKeyboardEntries() async throws {
        logger.info("Removing all keyboard entries via direct write")

        let plistContent: [String: Any] = ["keyboardtype": [:]]
        try await writePlist(plistContent)
        logger.info("Successfully removed all keyboard entries")
    }

    /// Write plist using osascript with administrator privileges
    private func writePlist(_ content: [String: Any]) async throws {
        // Serialize to XML plist
        let data = try PropertyListSerialization.data(
            fromPropertyList: content,
            format: .xml,
            options: 0
        )

        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw DirectWriteError.serializationFailed
        }

        // Escape for shell
        let escaped = xmlString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")

        // Use osascript to write with admin privileges
        let script = """
        do shell script "echo \\"\(escaped)\\" > '\(plistPath)'" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"

                // Check if user canceled
                if errorMsg.contains("User canceled") || errorMsg.contains("-128") {
                    throw DirectWriteError.userCanceled
                }

                throw DirectWriteError.scriptFailed(errorMsg)
            }
        } catch let error as DirectWriteError {
            throw error
        } catch {
            throw DirectWriteError.executionFailed(error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum DirectWriteError: LocalizedError {
    case serializationFailed
    case userCanceled
    case scriptFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serializationFailed:
            return "Failed to serialize plist data"
        case .userCanceled:
            return "User canceled the operation"
        case .scriptFailed(let msg):
            return "Script failed: \(msg)"
        case .executionFailed(let msg):
            return "Execution failed: \(msg)"
        }
    }
}
