import Foundation

public final class LocalKnowledgeStore: @unchecked Sendable {
    private enum Keys {
        static let vaultPath = "oceanpet.obsidian-vault"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var vaultURL: URL? {
        guard let path = defaults.string(forKey: Keys.vaultPath), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public func setVault(_ url: URL?) {
        if let url {
            defaults.set(url.standardizedFileURL.path, forKey: Keys.vaultPath)
        } else {
            defaults.removeObject(forKey: Keys.vaultPath)
        }
    }

    public func search(query: String) async -> String {
        guard let vaultURL else { return "" }
        return await Task.detached(priority: .userInitiated) {
            Self.search(vault: vaultURL, query: query)
        }.value
    }

    static func search(vault: URL, query: String) -> String {
        let tokens = queryTokens(query)
        guard !tokens.isEmpty else { return "" }

        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: vault,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return "" }

        struct Match {
            let score: Int
            let title: String
            let snippet: String
        }

        var matches: [Match] = []
        var visited = 0
        for case let fileURL as URL in enumerator {
            guard visited < 4_000 else { break }
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            visited += 1
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= 200_000,
                  let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let lower = text.lowercased()
            let title = fileURL.deletingPathExtension().lastPathComponent
            let lowerTitle = title.lowercased()
            var score = 0
            var firstOffset: Int?
            for token in tokens {
                let titleHits = lowerTitle.components(separatedBy: token).count - 1
                let bodyHits = min(lower.components(separatedBy: token).count - 1, 12)
                score += titleHits * 4 + bodyHits
                if firstOffset == nil, let range = lower.range(of: token) {
                    firstOffset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                }
            }
            guard score > 0 else { continue }
            matches.append(Match(score: score, title: title, snippet: snippet(from: text, around: firstOffset)))
        }

        let best = matches.sorted {
            $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score
        }.prefix(4)
        guard !best.isEmpty else { return "" }

        return best.map { "【来源：\($0.title)】\n\($0.snippet)" }.joined(separator: "\n---\n")
    }

    static func queryTokens(_ query: String) -> Set<String> {
        let lower = query.lowercased()
        var result = Set<String>()
        let words = lower.split { !$0.isLetter && !$0.isNumber }
        for word in words where word.count >= 2 {
            result.insert(String(word))
        }

        let chinese = Array(lower.filter { character in
            character.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(Int(scalar.value))
            }
        })
        if chinese.count == 1 { result.insert(String(chinese[0])) }
        if chinese.count >= 2 {
            for index in 0..<(chinese.count - 1) {
                result.insert(String(chinese[index...index + 1]))
            }
        }
        return result
    }

    private static func snippet(from text: String, around centerOffset: Int?) -> String {
        guard !text.isEmpty else { return "" }
        let startOffset = max(min(centerOffset ?? 0, text.count) - 100, 0)
        let endOffset = min(startOffset + 420, text.count)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(text.startIndex, offsetBy: endOffset)
        return text[start..<end]
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
