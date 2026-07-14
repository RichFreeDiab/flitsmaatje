import Foundation

/// Synchrone boot-log vóór alles — overleeft crashes die AppLogger missen.
enum BootLogger {
    private static let fileName = "boot.log"
    private static let maxBytes = 64_000
    private static var didWriteProcessStart = false

    private static var logPath: String {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfig.appGroupID
        ) {
            return url.appendingPathComponent(fileName).path
        }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(fileName)
    }

    static func mark(_ message: String) {
        if !didWriteProcessStart {
            didWriteProcessStart = true
            writeLine("process-start")
        }
        writeLine(message)
    }

    static func readAll() -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func upload() {
        uploadAsync()
    }

    static func uploadAsync() {
        let boot = readAll()
        let diagnostic = AppLogger.readAllSync()
        let body = """
        === BOOT LOG ===
        \(boot.isEmpty ? "(leeg)" : boot)
        === DIAGNOSTIC LOG ===
        \(diagnostic.isEmpty ? "(leeg)" : diagnostic)
        """
        AppLogger.uploadRaw(body, reason: "boot")
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

    private static func writeLine(_ message: String) {
        let line = "[\(isoTimestamp())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let path = logPath
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else if let url = URL(string: "file://\(path)") {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
        trimIfNeeded(path: path)
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
