import Foundation

public final class DeepSeekClient {
    public enum ClientError: LocalizedError {
        case invalidResponse
        case invalidConfiguration(String)
        case server(status: Int, message: String)
        case emptyReply(reason: String?)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return "DeepSeek 返回了无法识别的数据。"
            case .invalidConfiguration(let detail): return "DeepSeek 配置有误：\(detail)"
            case .server(let status, let message): return "DeepSeek 请求失败（\(status)）：\(message)"
            case .emptyReply(let reason):
                switch reason {
                case "content_filter": return "DeepSeek 没有生成这条内容，请换一种说法。"
                case "insufficient_system_resource": return "DeepSeek 当前繁忙，自动重试后仍未返回回复。"
                case "length": return "DeepSeek 的回复达到长度上限，请再试一次。"
                case .some(let value): return "DeepSeek 没有返回回复（\(value)），请再试一次。"
                case nil: return "DeepSeek 没有返回回复，自动重试仍未成功。"
                }
            }
        }
    }

    private struct APIMessage: Codable {
        let role: String
        let content: String
    }

    private struct ResponseFormat: Codable { let type: String }
    private struct ThinkingMode: Codable { let type: String }

    private struct CompletionRequest: Codable {
        let model: String
        let messages: [APIMessage]
        let responseFormat: ResponseFormat?
        let thinking: ThinkingMode
        let maxTokens: Int
        let temperature: Double

        enum CodingKeys: String, CodingKey {
            case model, messages, thinking, temperature
            case responseFormat = "response_format"
            case maxTokens = "max_tokens"
        }
    }

    private struct CompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable { let content: String? }
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
        let choices: [Choice]
    }

    private struct APIErrorEnvelope: Codable {
        struct APIError: Codable { let message: String }
        let error: APIError?
    }

    private let session: URLSession
    private let retryDelay: Duration

    public init(session: URLSession = .shared, retryDelay: Duration = .milliseconds(450)) {
        self.session = session
        self.retryDelay = retryDelay
    }

    public func reply(
        configuration: DeepSeekConfiguration,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> CharacterReply {
        let endpoint = try endpoint(for: configuration.baseURL)
        let context = Array(history.suffix(20)).map {
            APIMessage(role: $0.role.rawValue, content: $0.content)
        }
        var lastFinishReason: String?
        for attempt in 0..<2 {
            let payload = CompletionRequest(
                model: configuration.model,
                messages: [APIMessage(role: "system", content: systemPrompt)] + context,
                responseFormat: attempt == 0 ? ResponseFormat(type: "json_object") : nil,
                thinking: ThinkingMode(type: "disabled"),
                maxTokens: attempt == 0 ? 280 : 420,
                temperature: attempt == 0 ? 0.9 : 0.7
            )

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 45
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                if attempt == 0, http.statusCode == 429 || http.statusCode >= 500 {
                    try await Task.sleep(for: retryDelay)
                    continue
                }
                let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
                let fallback = String(data: data, encoding: .utf8) ?? "未知错误"
                throw ClientError.server(status: http.statusCode, message: envelope?.error?.message ?? fallback)
            }

            let choice = try JSONDecoder().decode(CompletionResponse.self, from: data).choices.first
            lastFinishReason = choice?.finishReason
            let raw = choice?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !raw.isEmpty {
                return decodeReply(raw)
            }
            if attempt == 0 {
                try await Task.sleep(for: retryDelay)
            }
        }
        throw ClientError.emptyReply(reason: lastFinishReason)
    }

    private func endpoint(for baseURL: String) throws -> URL {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            throw ClientError.invalidConfiguration("baseURL 不是有效的网址。")
        }
        if url.path.hasSuffix("/chat/completions") {
            return url
        }
        return url.appendingPathComponent("chat/completions")
    }

    private func decodeReply(_ raw: String) -> CharacterReply {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = decodeCharacterReply(trimmed) { return direct }

        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace <= lastBrace,
           let extracted = decodeCharacterReply(String(trimmed[firstBrace...lastBrace])) {
            return extracted
        }
        return CharacterReply(reply: trimmed, emotion: PetVisualState.talking.rawValue)
    }

    private func decodeCharacterReply(_ value: String) -> CharacterReply? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CharacterReply.self, from: data)
    }
}
