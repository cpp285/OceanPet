import Foundation

public struct ChatMessage: Codable, Identifiable, Equatable {
    public enum Role: String, Codable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public let content: String
    public let createdAt: Date

    public init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct CharacterReply: Codable, Equatable {
    public let reply: String
    public let emotion: String
}
