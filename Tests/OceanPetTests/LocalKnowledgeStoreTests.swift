import Foundation
import XCTest
@testable import OceanPet

final class LocalKnowledgeStoreTests: XCTestCase {
    func testSearchRanksTitleAndReturnsSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OceanPetKnowledge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "蟹堡的秘密配方需要新鲜生菜，海绵宝宝做蟹堡时非常认真。"
            .write(to: root.appendingPathComponent("蟹堡笔记.md"), atomically: true, encoding: .utf8)
        try "今天和派大星去抓水母。"
            .write(to: root.appendingPathComponent("水母日记.md"), atomically: true, encoding: .utf8)

        let result = LocalKnowledgeStore.search(vault: root, query: "蟹堡怎么做")
        XCTAssertTrue(result.contains("来源：蟹堡笔记"))
        XCTAssertTrue(result.contains("新鲜生菜"))
        XCTAssertFalse(result.contains("来源：水母日记"))
    }

    func testChineseQueryCreatesBigrams() {
        let tokens = LocalKnowledgeStore.queryTokens("海绵宝宝")
        XCTAssertTrue(tokens.contains("海绵"))
        XCTAssertTrue(tokens.contains("宝宝"))
    }
}
