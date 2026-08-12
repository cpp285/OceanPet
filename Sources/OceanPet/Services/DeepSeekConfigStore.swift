import Foundation

public struct DeepSeekConfiguration: Codable, Equatable {
    public static let defaultModel = "deepseek-v4-flash"
    public static let defaultBaseURL = "https://api.deepseek.com"

    public let apiKey: String
    public let model: String
    public let baseURL: String

    public init(
        apiKey: String,
        model: String = DeepSeekConfiguration.defaultModel,
        baseURL: String = DeepSeekConfiguration.defaultBaseURL
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? Self.defaultBaseURL
    }
}

public final class DeepSeekConfigStore {
    private struct FileConfiguration: Codable {
        let deepseek: DeepSeekConfiguration
    }

    public enum ConfigError: LocalizedError {
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let detail):
                return "无法读取 config.json：\(detail)"
            }
        }
    }

    public let configURL: URL

    public init(configURL: URL = AppPaths.config) {
        self.configURL = configURL
    }

    public func ensureTemplateExists() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !fileManager.fileExists(atPath: configURL.path) else { return }

        let template = FileConfiguration(deepseek: DeepSeekConfiguration(apiKey: ""))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(template)
        try data.write(to: configURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    /// Reload the file for every request so saved edits take effect immediately.
    public func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> DeepSeekConfiguration {
        try ensureTemplateExists()
        do {
            let data = try Data(contentsOf: configURL)
            let file = try JSONDecoder().decode(FileConfiguration.self, from: data)
            return DeepSeekConfiguration(
                apiKey: nonEmpty(environment["DEEPSEEK_API_KEY"]) ?? file.deepseek.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                model: nonEmpty(environment["DEEPSEEK_MODEL"]) ?? nonEmpty(file.deepseek.model) ?? DeepSeekConfiguration.defaultModel,
                baseURL: nonEmpty(environment["DEEPSEEK_BASE_URL"]) ?? nonEmpty(file.deepseek.baseURL) ?? DeepSeekConfiguration.defaultBaseURL
            )
        } catch {
            throw ConfigError.unreadable(error.localizedDescription)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
