import Foundation

enum TranslationError: LocalizedError {
    case notConfigured
    case badURL(String)
    case http(status: Int, body: String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "还没配置 API key，先到主 App 里填一下。"
        case .badURL(let url):
            return "Base URL 不合法：\(url)"
        case .http(let status, let body):
            let trimmed = body.prefix(300)
            return "接口返回 \(status)：\(trimmed)"
        case .transport(let error):
            return "网络错误：\(error.localizedDescription)"
        }
    }
}

/// A streaming chat-completion backend.
protocol TranslationProvider: Sendable {
    /// Yields incremental text deltas. The full result is the concatenation of
    /// everything yielded.
    func stream(_ messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}

extension TranslationProvider {
    /// Convenience wrapper for callers that only want the finished string.
    func complete(_ messages: [ChatMessage]) async throws -> String {
        var result = ""
        for try await delta in stream(messages) {
            result += delta
        }
        return result
    }
}
