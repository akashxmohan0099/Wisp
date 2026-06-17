import Foundation

public enum TranscriptCleaner {
    public static func cleaned(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fillerPatterns = [
            #"(?i)\b(um+|uh+|erm+|ah+)\b[, ]*"#,
            #"(?i)\b(you know|i mean|kind of|sort of)\b[, ]*"#
        ]

        for pattern in fillerPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        result = result
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else {
            return ""
        }

        result = result.prefix(1).uppercased() + result.dropFirst()

        if let last = result.last, !".!?".contains(last) {
            result += "."
        }

        return result
    }
}
