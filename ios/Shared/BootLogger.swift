import Foundation

/// Boot breadcrumbs that must never block the main thread.
/// Previous version held a lock during App Group file I/O and could freeze the UI
/// once boot.log grew large (no 586 uploads = hang, not a clean crash).
enum BootLogger {
    private static let fileName = "boot.log"
    private static let maxBytes = 24_000
    private static let maxMemoryLines = 100
    private static let queue = DispatchQueue(label: "nl.readvanes.flitsmaatje.bootlog", qos: .utility)

    private static var didWriteProcessStart = false
    private static var memoryLines: [String] = []

    private static var logPaths: [String] {
        var paths: [String] = []
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfig.appGroupID
        ) {
            paths.append(group.appendingPathComponent(fileName).path)
        }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            paths.append(docs.appendingPathComponent(fileName).path)
        }
        paths.append((NSTemporaryDirectory() as NSString).appendingPathComponent(fileName))
        return Array(Set(paths))
    }

    /// Never blocks the caller. Safe from MainActor / button handlers.
    static func mark(_ message: String) {
        let stamped = "[\(isoTimestamp())] \(message)"
        queue.async {
            if !didWriteProcessStart {
                didWriteProcessStart = true
                resetFilesForNewSession()
                appendLine("[\(isoTimestamp())] process-start")
            }
            appendLine(stamped)
        }
    }

    static func readAll() -> String {
        queue.sync {
            if !memoryLines.isEmpty {
                return memoryLines.joined(separator: "\n")
            }
            for path in logPaths {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let text = String(data: data, encoding: .utf8),
                      !text.isEmpty else { continue }
                return text
            }
            return ""
        }
    }

    static func upload() {
        uploadAsync()
    }

    static func uploadAsync() {
        queue.async {
            let boot = memoryLines.isEmpty ? readFilesUnlocked() : memoryLines.joined(separator: "\n")
            let diagnostic = AppLogger.readAllSync()
            let body = """
            === BOOT LOG ===
            \(boot.isEmpty ? "(leeg)" : boot)
            === DIAGNOSTIC LOG ===
            \(diagnostic.isEmpty ? "(leeg)" : diagnostic)
            """
            AppLogger.uploadRaw(body, reason: "boot")
        }
    }

    static func uploadSync(timeout: TimeInterval = 2.5) {
        let boot = readAll()
        let diagnostic = AppLogger.readAllSync()
        let body = """
        === BOOT LOG ===
        \(boot.isEmpty ? "(leeg)" : boot)
        === DIAGNOSTIC LOG ===
        \(diagnostic.isEmpty ? "(leeg)" : diagnostic)
        """
        AppLogger.uploadRawSync(body, reason: "boot", timeout: timeout)
    }

    private static func resetFilesForNewSession() {
        // Keep only a short tail so cold-start I/O stays cheap.
        let previous = readFilesUnlocked()
        let tail = previous
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(20)
            .joined(separator: "\n")
        let seed = tail.isEmpty ? "" : tail + "\n--- new session ---\n"
        for path in logPaths {
            try? seed.write(toFile: path, atomically: true, encoding: .utf8)
        }
        memoryLines = seed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func appendLine(_ line: String) {
        memoryLines.append(line)
        if memoryLines.count > maxMemoryLines {
            memoryLines.removeFirst(memoryLines.count - maxMemoryLines)
        }

        guard let data = (line + "\n").data(using: .utf8) else { return }
        for path in logPaths {
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            if let handle = FileHandle(forWritingAtPath: path) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            }
            trimIfNeeded(path: path)
        }
    }

    private static func readFilesUnlocked() -> String {
        for path in logPaths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let text = String(data: data, encoding: .utf8),
                  !text.isEmpty else { continue }
            return text
        }
        return ""
    }

    private static func isoTimestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    private static func trimIfNeeded(path: String) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int,
              size > maxBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        let trimmed = text.split(separator: "\n").suffix(60).joined(separator: "\n")
        try? trimmed.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
