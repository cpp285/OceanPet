import Foundation

public final class ConversationPersistence {
    public init() {}

    public func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: AppPaths.conversation),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return [] }
        return messages
    }

    public func save(_ messages: [ChatMessage]) {
        let recent = Array(messages.suffix(40))
        guard let data = try? JSONEncoder().encode(recent) else { return }
        try? data.write(to: AppPaths.conversation, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: AppPaths.conversation)
    }
}
