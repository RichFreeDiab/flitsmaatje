import Foundation

/// Synchrone boot-log vóór alles — overleeft crashes die AppLogger missen.
enum BootLogger {
    private static let fileName = "boot.log"
    private static let maxBytes = 64_000

    private static var logPath: String {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfig.appGroupID
        ) {
            return url.appendingPathComponent(fileName).path
        }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(fileName)
    }

    private static let booted: Void = {
        mark("process-start")
    }()

    static func mark(_ message: String) {
        _ = booted
        let line = "[\(isoTimestamp())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let path = logPath
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        trimIfNeeded(path: path)
    }

    static func readAll() -> String {
        _ = booted
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func upload() {
        uploadSync(timeout: 0.1)
    }

    /// Blokkeert kort zodat logs de server bereiken vóór een crash.
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
        let trimmed = text.split(separator: "\n").suffix(80).joined(separator: "\n")
        try? trimmed.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
