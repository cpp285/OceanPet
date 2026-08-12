import AppKit
import Foundation

public struct PetGrid: Codable, Equatable {
    public let columns: Int
    public let rows: Int
}

public struct PetPersona: Codable, Equatable {
    public let greeting: String
    public let systemPrompt: String
}

public struct PetPoint: Codable, Equatable {
    public let x: Double
    public let y: Double
}

public struct EyeTrackingConfig: Codable, Equatable {
    public let leftEye: PetPoint
    public let rightEye: PetPoint
    public let maskSize: PetPoint
    public let pupilSize: PetPoint
    public let maxOffset: PetPoint
    public let visibleStates: [String]
}

public struct PetManifest: Codable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let spokenName: String?
    public let wakeWords: [String]?
    public let pixelArt: Bool?
    public let spriteSheet: String
    public let grid: PetGrid
    public let stateFrames: [String: [Int]]
    public let frameDuration: Double
    public let walkFrameDuration: Double?
    public let persona: PetPersona
    public let eyeTracking: EyeTrackingConfig?

    public func frames(for state: PetVisualState) -> [Int] {
        stateFrames[state.rawValue] ?? stateFrames[PetVisualState.idle.rawValue] ?? [0]
    }

    public var conversationName: String {
        if let name = spokenName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return displayName
    }

    public var effectiveWakeWords: [String] {
        let configured = (wakeWords ?? []).compactMap { word -> String? in
            let value = word.replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return configured.isEmpty ? [conversationName.replacingOccurrences(of: " ", with: "")] : configured
    }

    public var usesPixelArtFiltering: Bool { pixelArt ?? true }
}

public enum PetVisualState: String, Codable, CaseIterable {
    case idle
    case talking
    case happy
    case walkLeft
    case walkRight
    case confused
    case sleepy

    public init(apiValue: String) {
        self = PetVisualState(rawValue: apiValue) ?? .idle
    }
}

public struct PetCharacter: Identifiable, Equatable {
    public let manifest: PetManifest
    public let directoryURL: URL
    public let isBundled: Bool

    public var id: String { manifest.id }
    public var spriteSheetURL: URL { directoryURL.appendingPathComponent(manifest.spriteSheet) }

    public static func == (lhs: PetCharacter, rhs: PetCharacter) -> Bool {
        lhs.manifest == rhs.manifest && lhs.directoryURL == rhs.directoryURL
    }
}

public enum PetPackageError: LocalizedError {
    case missingManifest
    case invalidManifest
    case unsafeIdentifier
    case unsafeSpritePath
    case missingSprite
    case duplicateIdentifier

    public var errorDescription: String? {
        switch self {
        case .missingManifest: return "角色包中缺少 pet.json。"
        case .invalidManifest: return "pet.json 格式不正确，或网格尺寸无效。"
        case .unsafeIdentifier: return "角色 id 只能包含字母、数字、短横线和下划线。"
        case .unsafeSpritePath: return "精灵图必须直接放在角色包目录中。"
        case .missingSprite: return "找不到 pet.json 指定的精灵图。"
        case .duplicateIdentifier: return "已经存在相同 id 的角色，请先修改 pet.json 中的 id。"
        }
    }
}
