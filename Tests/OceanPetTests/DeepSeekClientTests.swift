import Foundation
import XCTest
@testable import OceanPet

final class DeepSeekClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testDecodesStructuredCharacterReply() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "deepseek-v4-flash")
            XCTAssertEqual((json["thinking"] as? [String: String])?["type"], "disabled")
            XCTAssertEqual((json["response_format"] as? [String: String])?["type"], "json_object")

            let response = #"{"choices":[{"message":{"content":"{\"reply\":\"今天去抓水母吧！\",\"emotion\":\"happy\"}"}}]}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = DeepSeekClient(session: URLSession(configuration: configuration))
        let result = try await client.reply(
            configuration: DeepSeekConfiguration(apiKey: "test-key"),
            systemPrompt: "只返回 JSON",
            history: [ChatMessage(role: .user, content: "今天做什么？")]
        )

        XCTAssertEqual(result.reply, "今天去抓水母吧！")
        XCTAssertEqual(result.emotion, "happy")
    }

    func testRetriesEmptyReplyWithoutJSONMode() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            let body = try requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            if requestCount == 1 {
                XCTAssertNotNil(json["response_format"])
                let response = #"{"choices":[{"finish_reason":"insufficient_system_resource","message":{"content":""}}]}"#
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(response.utf8)
                )
            }

            XCTAssertNil(json["response_format"])
            let response = #"{"choices":[{"finish_reason":"stop","message":{"content":"LLM 就是负责理解和生成语言的大模型。"}}]}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = DeepSeekClient(
            session: URLSession(configuration: configuration),
            retryDelay: .zero
        )
        let result = try await client.reply(
            configuration: DeepSeekConfiguration(apiKey: "test-key"),
            systemPrompt: "只返回 JSON",
            history: [ChatMessage(role: .user, content: "LLM 是什么？")]
        )

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(result.reply, "LLM 就是负责理解和生成语言的大模型。")
        XCTAssertEqual(result.emotion, "talking")
    }
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let data = request.httpBody { return data }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
        if count == 0 { break }
        result.append(buffer, count: count)
    }
    return result
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
