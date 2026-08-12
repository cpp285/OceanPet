import AppKit
import XCTest
@testable import OceanPet

final class ManifestTests: XCTestCase {
    func testUnknownEmotionFallsBackToIdle() {
        XCTAssertEqual(PetVisualState(apiValue: "surprised"), .idle)
        XCTAssertEqual(PetVisualState(apiValue: "happy"), .happy)
    }

    @MainActor
    func testBundledCharacterLoads() {
        let store = CharacterStore()
        XCTAssertEqual(store.active?.id, "spongebob-pixel")
        XCTAssertNotNil(store.active.flatMap { NSImage(contentsOf: $0.spriteSheetURL) })
        XCTAssertEqual(Set(store.characters.map(\.id)), Set(["spongebob-pixel", "patrick-pixel"]))
        XCTAssertTrue(store.characters.allSatisfy { NSImage(contentsOf: $0.spriteSheetURL) != nil })
        let spongeBob = store.characters.first { $0.id == "spongebob-pixel" }
        let patrick = store.characters.first { $0.id == "patrick-pixel" }
        XCTAssertEqual(spongeBob?.manifest.conversationName, "海绵宝宝")
        XCTAssertEqual(spongeBob?.manifest.effectiveWakeWords, ["海绵宝宝", "海绵宝"])
        XCTAssertEqual(patrick?.manifest.conversationName, "派大星")
        XCTAssertEqual(patrick?.manifest.effectiveWakeWords, ["派大星"])
        XCTAssertEqual(patrick?.manifest.frames(for: .idle), [0])
        XCTAssertEqual(spongeBob?.manifest.usesPixelArtFiltering, true)
        XCTAssertEqual(patrick?.manifest.usesPixelArtFiltering, false)
    }
}
