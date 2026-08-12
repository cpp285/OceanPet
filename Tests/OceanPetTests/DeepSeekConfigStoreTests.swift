import Foundation
import XCTest
@testable import OceanPet

final class DeepSeekConfigStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OceanPetConfigTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testCreatesReadableTemplate() throws {
        let store = DeepSeekConfigStore(configURL: directory.appendingPathComponent("config.json"))

        try store.ensureTemplateExists()
        let configuration = try store.load(environment: [:])

        XCTAssertEqual(configuration.apiKey, "")
        XCTAssertEqual(configuration.model, "deepseek-v4-flash")
        XCTAssertEqual(configuration.baseURL, "https://api.deepseek.com")
    }

    func testReloadsEditedFileAndAppliesEnvironmentOverrides() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.json")
        let json = #"{"deepseek":{"apiKey":"file-key","model":"file-model","baseURL":"https://file.example/v1"}}"#
        try Data(json.utf8).write(to: configURL)
        let store = DeepSeekConfigStore(configURL: configURL)

        XCTAssertEqual(try store.load(environment: [:]).apiKey, "file-key")

        let overridden = try store.load(environment: [
            "DEEPSEEK_API_KEY": "environment-key",
            "DEEPSEEK_MODEL": "environment-model",
            "DEEPSEEK_BASE_URL": "https://environment.example"
        ])
        XCTAssertEqual(overridden.apiKey, "environment-key")
        XCTAssertEqual(overridden.model, "environment-model")
        XCTAssertEqual(overridden.baseURL, "https://environment.example")
    }
}
