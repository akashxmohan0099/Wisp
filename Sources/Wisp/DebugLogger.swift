import Foundation

enum DebugLogger {
    private static let queue = DispatchQueue(label: "Wisp.DebugLogger")
    private static let logURL = URL(fileURLWithPath: "/tmp/wisp.log")

    static func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: logURL)
        }
    }

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"

        queue.async {
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: logURL.path) {
                guard let handle = try? FileHandle(forWritingTo: logURL) else {
                    return
                }

                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }

            try? data.write(to: logURL, options: .atomic)
        }
    }
}
