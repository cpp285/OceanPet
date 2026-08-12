import AppKit
import Foundation

@MainActor
public final class CharacterStore: ObservableObject {
    @Published public private(set) var characters: [PetCharacter] = []
    @Published public private(set) var active: PetCharacter?

    private let decoder = JSONDecoder()
    private let selectedKey = "oceanpet.selected-character"

    public init() {
        reload()
    }

    public func reload() {
        var loaded: [PetCharacter] = []
        if let bundledRoot = bundledCharactersRoot(),
           let urls = try? FileManager.default.contentsOfDirectory(at: bundledRoot, includingPropertiesForKeys: nil) {
            loaded.append(contentsOf: urls.compactMap { try? loadCharacter(at: $0, bundled: true) })
        }
        if let urls = try? FileManager.default.contentsOfDirectory(at: AppPaths.characters, includingPropertiesForKeys: nil) {
            loaded.append(contentsOf: urls.compactMap { try? loadCharacter(at: $0, bundled: false) })
        }
        characters = loaded.sorted { $0.manifest.displayName.localizedCompare($1.manifest.displayName) == .orderedAscending }
        let preferred = UserDefaults.standard.string(forKey: selectedKey)
        active = characters.first { $0.id == preferred }
            ?? characters.first { $0.id == "spongebob-pixel" }
            ?? characters.first
    }

    private func bundledCharactersRoot() -> URL? {
        // A packaged .app keeps the SwiftPM resource bundle in Contents/Resources
        // so codesigning and Gatekeeper see a conventional application layout.
        if let resourceURL = Bundle.main.resourceURL {
            let packaged = resourceURL
                .appendingPathComponent("OceanPet_OceanPet.bundle", isDirectory: true)
                .appendingPathComponent("Resources/Characters", isDirectory: true)
            if FileManager.default.fileExists(atPath: packaged.path) { return packaged }
        }
        // `swift run OceanPet` resolves resources through SwiftPM's generated bundle.
        return Bundle.module.url(forResource: "Characters", withExtension: nil, subdirectory: "Resources")
    }

    public func select(_ character: PetCharacter) {
        active = character
        UserDefaults.standard.set(character.id, forKey: selectedKey)
    }

    @discardableResult
    public func importPackage(from source: URL) throws -> PetCharacter {
        let candidate = try loadCharacter(at: source, bundled: false)
        guard !characters.contains(where: { $0.id == candidate.id }) else { throw PetPackageError.duplicateIdentifier }
        let target = AppPaths.characters.appendingPathComponent(candidate.id, isDirectory: true)
        try FileManager.default.copyItem(at: source, to: target)
        reload()
        guard let imported = characters.first(where: { $0.id == candidate.id }) else { throw PetPackageError.invalidManifest }
        select(imported)
        return imported
    }

    private func loadCharacter(at directory: URL, bundled: Bool) throws -> PetCharacter {
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw PetPackageError.missingManifest }
        let manifest: PetManifest
        do {
            manifest = try decoder.decode(PetManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw PetPackageError.invalidManifest
        }
        guard manifest.grid.columns > 0, manifest.grid.rows > 0,
              manifest.grid.columns * manifest.grid.rows <= 256 else { throw PetPackageError.invalidManifest }
        let validID = manifest.id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
        guard validID else { throw PetPackageError.unsafeIdentifier }
        guard URL(fileURLWithPath: manifest.spriteSheet).lastPathComponent == manifest.spriteSheet else {
            throw PetPackageError.unsafeSpritePath
        }
        let spriteURL = directory.appendingPathComponent(manifest.spriteSheet)
        guard FileManager.default.fileExists(atPath: spriteURL.path), NSImage(contentsOf: spriteURL) != nil else {
            throw PetPackageError.missingSprite
        }
        return PetCharacter(manifest: manifest, directoryURL: directory, isBundled: bundled)
    }
}
