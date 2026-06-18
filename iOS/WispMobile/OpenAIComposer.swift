import Foundation

struct OpenAIComposer {
    let apiKey: String

    func compose(_ transcript: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ResponsesRequest(
            model: "gpt-4.1-mini",
            input: [
                ResponsesMessage(
                    role: "system",
                    content: "Rewrite the user's dictated text into clear, paste-ready writing. Preserve intent, remove filler, fix grammar, and keep it concise. Return only the rewritten text."
                ),
                ResponsesMessage(role: "user", content: transcript)
            ],
            temperature: 0.2,
            maxOutputTokens: 700
        )

        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw OpenAIComposerError.requestFailed
        }

        let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        let text = decoded.output
            .flatMap(\.content)
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? transcript : text
    }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: [ResponsesMessage]
    let temperature: Double
    let maxOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case maxOutputTokens = "max_output_tokens"
    }
}

private struct ResponsesMessage: Encodable {
    let role: String
    let content: String
}

private struct ResponsesResponse: Decodable {
    let output: [ResponsesOutput]
}

private struct ResponsesOutput: Decodable {
    let content: [ResponsesContent]
}

private struct ResponsesContent: Decodable {
    let text: String?
}

private enum OpenAIComposerError: Error {
    case requestFailed
}
