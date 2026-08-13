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
        XCTAssertEqual(
            Set(store.characters.map(\.id)),
            Set(["spongebob-pixel", "patrick-pixel", "squidward-cartoon", "mr-krabs-cartoon"])
        )
        XCTAssertTrue(store.characters.allSatisfy { NSImage(contentsOf: $0.spriteSheetURL) != nil })
        let spongeBob = store.characters.first { $0.id == "spongebob-pixel" }
        let patrick = store.characters.first { $0.id == "patrick-pixel" }
        let squidward = store.characters.first { $0.id == "squidward-cartoon" }
        let mrKrabs = store.characters.first { $0.id == "mr-krabs-cartoon" }
        XCTAssertEqual(spongeBob?.manifest.conversationName, "海绵宝宝")
        XCTAssertEqual(spongeBob?.manifest.displayName, "卡通海绵宝宝")
        XCTAssertEqual(spongeBob?.manifest.effectiveWakeWords, ["海绵宝宝", "海绵宝"])
        XCTAssertEqual(patrick?.manifest.conversationName, "派大星")
        XCTAssertEqual(patrick?.manifest.effectiveWakeWords, ["派大星"])
        XCTAssertEqual(patrick?.manifest.frames(for: .idle), [0])
        XCTAssertEqual(squidward?.manifest.conversationName, "章鱼哥")
        XCTAssertEqual(squidward?.manifest.effectiveWakeWords, ["章鱼哥"])
        XCTAssertEqual(squidward?.manifest.frames(for: .idle), [0])
        XCTAssertEqual(mrKrabs?.manifest.conversationName, "蟹老板")
        XCTAssertEqual(mrKrabs?.manifest.effectiveWakeWords, ["蟹老板", "尤金"])
        XCTAssertEqual(mrKrabs?.manifest.frames(for: .idle), [0])
        XCTAssertTrue(store.characters.allSatisfy { $0.manifest.grid == PetGrid(columns: 6, rows: 2) })
        XCTAssertTrue(store.characters.allSatisfy {
            $0.manifest.frames(for: .walkLeft) == [4, 5]
                && $0.manifest.frames(for: .walkRight) == [6, 7]
                && $0.manifest.walkFrameDuration == 0.30
        })
        XCTAssertEqual(spongeBob?.manifest.usesPixelArtFiltering, false)
        XCTAssertEqual(patrick?.manifest.usesPixelArtFiltering, false)
        XCTAssertEqual(squidward?.manifest.usesPixelArtFiltering, false)
        XCTAssertEqual(mrKrabs?.manifest.usesPixelArtFiltering, false)

        guard let squidward,
              let image = NSImage(contentsOf: squidward.spriteSheetURL),
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else {
            return XCTFail("章鱼哥精灵图无法读取")
        }
        let sharedBoundary = bitmap.pixelsWide * 3 / squidward.manifest.grid.columns
        for y in 0..<bitmap.pixelsHigh {
            let beforeBoundary = bitmap.colorAt(x: sharedBoundary - 1, y: y)?.alphaComponent ?? 0
            let afterBoundary = bitmap.colorAt(x: sharedBoundary, y: y)?.alphaComponent ?? 0
            XCTAssertLessThanOrEqual(beforeBoundary, 0.12, "说话帧右边缘存在串图")
            XCTAssertLessThanOrEqual(afterBoundary, 0.12, "吹奏帧左边缘存在串图")
        }
    }
}
