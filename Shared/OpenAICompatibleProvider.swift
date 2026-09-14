import Foundation

/// Talks to any OpenAI-shaped `/chat/completions` endpoint.
///
/// DeepSeek and MiniMax are both wire-compatible here, so switching providers
/// is a base-URL and model-name change rather than a code change. If a provider
/// ever diverges, subclass the request building rather than forking the whole
/// file.
struct OpenAICompatibleProvider: TranslationProvider {
    let baseURL: String
    let model: String
    let apiKey: String

    init(settings: AppSettings) {
        self.baseURL = settings.baseURL
        self.model = settings.model
        self.apiKey = settings.apiKey
    }

    func stream(_ messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else { throw TranslationError.notConfigured }

                    let request = try makeRequest(messages: messages)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        // Drain the body so the error message is actually useful —
                        // these APIs put the real reason (bad key, no quota, wrong
                        // model name) in the response body, not the status line.
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw TranslationError.http(status: http.statusCode, body: body)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { break }
                        if let delta = Self.parseDelta(payload), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as TranslationError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: TranslationError.transport(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(messages: [ChatMessage]) throws -> URLRequest {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/chat/completions") else {
            throw TranslationError.badURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            // Low but not zero: translation should be stable across keystrokes,
            // otherwise the streamed text visibly churns while you type.
            "temperature": 0.2,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Pulls `choices[0].delta.content` out of one SSE payload.
    private static func parseDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first
        else { return nil }

        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        // Some providers send a final non-streaming `message` object.
        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return nil
    }
}
