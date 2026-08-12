import Foundation

public enum AppPaths {
    public static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("OceanPet", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    public static let characters: URL = {
        let url = root.appendingPathComponent("Characters", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    public static let conversation = root.appendingPathComponent("conversation.json")
    public static let config = root.appendingPathComponent("config.json")
}
