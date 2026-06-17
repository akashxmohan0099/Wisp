import Foundation

enum LLMRefinementError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Set OPENAI_API_KEY or save a key at ~/Library/Application Support/Wisp/openai-key to enable Compose mode."
        case .invalidResponse:
            return "The AI compose response could not be read."
        case .requestFailed(let message):
            return message
        }
    }
}

struct LLMRefinementService {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    func compose(from transcript: String) async throws -> String {
        guard let apiKey = Self.resolveAPIKey() else {
            throw LLMRefinementError.missingAPIKey
        }

        let environment = ProcessInfo.processInfo.environment
        let model = environment["WISP_OPENAI_MODEL"] ?? environment["WHISP_OPENAI_MODEL"] ?? "gpt-4.1-mini"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let prompt = """
        Rewrite this dictated speech into the message the speaker intended.
        Preserve concrete facts, names, dates, numbers, and commitments.
        Remove filler words, false starts, and repeated phrasing.
        Keep it concise, natural, and paste-ready.
        Return only the final text.

        Dictation:
        \(transcript)
        """

        let body: [String: Any] = [
            "model": model,
            "input": prompt,
            "temperature": 0.2,
            "max_output_tokens": 700
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMRefinementError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "OpenAI request failed."
            throw LLMRefinementError.requestFailed(message)
        }

        guard let text = Self.extractOutputText(from: data) else {
            throw LLMRefinementError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveAPIKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let apiKey = trimmed(environment["OPENAI_API_KEY"]) {
            return apiKey
        }

        for url in apiKeyFileCandidates() {
            guard let contents = try? String(contentsOf: url, encoding: .utf8),
                  let apiKey = trimmed(contents) else {
                continue
            }

            return apiKey
        }

        return nil
    }

    private static func apiKeyFileCandidates() -> [URL] {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [
            base
                .appending(path: "Wisp", directoryHint: .isDirectory)
                .appending(path: "openai-key"),
            base
                .appending(path: "Whisp", directoryHint: .isDirectory)
                .appending(path: "openai-key")
        ]
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func extractOutputText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let outputText = object["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        guard let output = object["output"] as? [[String: Any]] else {
            return nil
        }

        var parts: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else {
                continue
            }
            for contentItem in content {
                if let text = contentItem["text"] as? String {
                    parts.append(text)
                }
            }
        }

        let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
