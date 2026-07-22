import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        }
    }
}

@MainActor
final class AppLogStore: ObservableObject {
    static let shared = AppLogStore()

    @Published private(set) var lines: [String] = []

    func reload() {
        lines = AppLogger.readRecentLines()
    }

    func append(_ line: String) {
        lines.append(line)
        if lines.count > 400 {
            lines.removeFirst(lines.count - 400)
        }
    }

    func clear() {
        AppLogger.clear()
        lines = []
    }
}

private func recordUnhandledException(_ exception: NSException) {
    let message = "CRASH \(exception.name.rawValue): \(exception.reason ?? "onbekend")"
    BootLogger.mark(message)
    AppLogger.writeSyncFromCrashHandler(message)
    for symbol in exception.callStackSymbols.prefix(16) {
        AppLogger.writeSyncFromCrashHandler("  \(symbol)")
    }
}

enum AppLogger {
    private static let subsystem = "nl.readvanes.flitsmaatje"
    private static let logFileName = "diagnostic.log"
    private static let maxFileBytes = 512_000
    private static let osLog = Logger(subsystem: subsystem, category: "app")
    private static let queue = DispatchQueue(label: "nl.readvanes.flitsmaatje.log", qos: .utility)
    private static var didInstall = false
    private static var uiUpdatesEnabled = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static var isMainApp: Bool {
        !Bundle.main.bundleURL.pathExtension.contains("appex")
    }

    static func install() {
        guard isMainApp, !didInstall else { return }
        didInstall = true
        NSSetUncaughtExceptionHandler(recordUnhandledException)
        markBootStage("logger-installed")
        uploadLogFile(reason: "previous-session")
    }

    static func markBootStage(_ stage: String) {
        writeSync("BOOT \(stage)", level: .info)
    }

    static func enableUIUpdates() {
        uiUpdatesEnabled = true
    }

    static func writeSyncFromCrashHandler(_ message: String) {
        writeSync(message, level: .error)
    }

    static func log(_ message: String, level: LogLevel = .info) {
        write(message, level: level)
    }

    static func error(_ message: String) {
        write(message, level: .error)
    }

    static func flush() {
        queue.sync {}
    }

    static func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: logFileURL())
        }
    }

    static func readRecentLines(limit: Int = 300) -> [String] {
        queue.sync {
            guard let data = try? Data(contentsOf: logFileURL()),
                  let text = String(data: data, encoding: .utf8) else {
                return []
            }
            let allLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if allLines.count <= limit {
                return allLines
            }
            return Array(allLines.suffix(limit))
        }
    }

    static func logFileURL() -> URL {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfig.appGroupID
        ) {
            return container.appendingPathComponent(logFileName)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(logFileName)
    }

    static func uploadLogFile(reason: String) {
        guard isMainApp else { return }
        // We are already on the serial log queue. Calling flush() here would
        // synchronously wait for this same queue and can freeze the app.
        queue.async {
            guard let data = try? Data(contentsOf: logFileURL()),
                  !data.isEmpty else { return }
            uploadData(data, reason: reason)
        }
    }

    static func uploadRaw(_ body: String, reason: String) {
        guard isMainApp, let data = body.data(using: .utf8), !data.isEmpty else { return }
        queue.async {
            uploadData(data, reason: reason)
        }
    }

    static func uploadRawSync(_ body: String, reason: String, timeout: TimeInterval = 2.5) {
        guard isMainApp, let data = body.data(using: .utf8), !data.isEmpty else { return }
        let sem = DispatchSemaphore(value: 0)
        queue.async {
            uploadData(data, reason: reason) {
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + timeout)
    }

    static func readAllSync() -> String {
        queue.sync {
            guard let data = try? Data(contentsOf: logFileURL()),
                  let text = String(data: data, encoding: .utf8) else {
                return ""
            }
            return text
        }
    }

    private static func uploadData(_ data: Data, reason: String, completion: (() -> Void)? = nil) {
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("/api/diagnostic-log"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(reason, forHTTPHeaderField: "X-Log-Reason")
        request.setValue(deviceLabel(), forHTTPHeaderField: "X-Device-Id")
        request.setValue(appVersionLabel(), forHTTPHeaderField: "X-App-Version")
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { _, _, _ in
            completion?()
        }.resume()
    }

    private static func deviceLabel() -> String {
        #if canImport(UIKit)
        return "\(UIDevice.current.model)-iOS\(UIDevice.current.systemVersion)"
        #else
        return "ios-device"
        #endif
    }

    private static func appVersionLabel() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version)-\(build)"
    }

    private static func write(_ message: String, level: LogLevel) {
        queue.async {
            writeSync(message, level: level)
        }
        osLog.log(level: level.osLogType, "\(message, privacy: .public)")
        guard isMainApp, uiUpdatesEnabled else { return }
        let line = formattedLine(message, level: level)
        Task { @MainActor in
            AppLogStore.shared.append(line)
        }
    }

    private static func writeSync(_ message: String, level: LogLevel) {
        let line = formattedLine(message, level: level)
        guard let data = (line + "\n").data(using: .utf8) else { return }

        let url = logFileURL()
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        trimIfNeeded(url: url, fileManager: fileManager)
    }

    private static func formattedLine(_ message: String, level: LogLevel) -> String {
        "[\(timestamp())] [\(level.rawValue)] \(message)"
    }

    private static func timestamp() -> String {
        dateFormatter.string(from: Date())
    }

    private static func trimIfNeeded(url: URL, fileManager: FileManager) {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size > maxFileBytes,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.suffix(250).joined(separator: "\n")
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }
}
