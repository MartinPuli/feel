import XCTest
@testable import Lantern

/// Serves canned HTTP replies and records the request, so the gateway's wire shape is checked without a network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        Self.lastRequest = request; Self.lastBody = body
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let (status, data) = handler(request, body)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class ChalkGatewayTests: XCTestCase {
    private let key = String(repeating: "k", count: 16)
    private func configuration(host: String = ChalkConfiguration.defaultHost, key: String? = nil, environment: String = "bnsb82aac313", model: String = ChalkConfiguration.defaultModel) -> ChalkConfiguration {
        ChalkConfiguration(apiHost: host, routerApiKey: key ?? self.key, environmentId: environment, model: model)
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
    override func tearDown() { StubURLProtocol.handler = nil; StubURLProtocol.lastRequest = nil; StubURLProtocol.lastBody = nil }

    func testConfigurationValidation() {
        XCTAssertTrue(configuration().isValid)
        XCTAssertFalse(configuration(host: "http://api.chalk.ai").isValid)
        XCTAssertFalse(configuration(host: "https://api.chalk.ai/?x=1").isValid)
        XCTAssertFalse(configuration(key: "short").isValid)
        XCTAssertFalse(configuration(key: "has a space in it").isValid)
        XCTAssertFalse(configuration(environment: "").isValid)
        XCTAssertFalse(configuration(environment: String(repeating: "e", count: 65)).isValid)
        XCTAssertFalse(configuration(model: "").isValid)
        XCTAssertEqual(ChalkConfiguration.defaultModel, "openai/gpt-6.1-sol")
    }

    func testRequestCarriesGatewayHeaders() throws {
        StubURLProtocol.handler = { _, _ in (200, Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)) }
        let gateway = ChalkGateway(configuration: configuration(), session: session())
        let done = expectation(description: "reply")
        var received: Result<String, Error>?
        gateway.complete(body: Data(#"{"model":"m"}"#.utf8), timeout: 5) { received = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try received?.get(), "OK")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.chalk.ai/v1/router/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Chalk-Env-Id"), "bnsb82aac313")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(StubURLProtocol.lastBody, Data(#"{"model":"m"}"#.utf8))
    }

    func testMalformedReplyIsFailure() {
        StubURLProtocol.handler = { _, _ in (200, Data("{}".utf8)) }
        let done = expectation(description: "reply")
        var received: Result<String, Error>?
        ChalkGateway(configuration: configuration(), session: session()).complete(body: Data("{}".utf8), timeout: 5) { received = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertThrowsError(try received?.get())
    }

    func testHTTPErrorIsFailure() {
        StubURLProtocol.handler = { _, _ in (401, Data(#"{"error":"nope"}"#.utf8)) }
        let done = expectation(description: "reply")
        var received: Result<String, Error>?
        ChalkGateway(configuration: configuration(), session: session()).complete(body: Data("{}".utf8), timeout: 5) { received = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertThrowsError(try received?.get())
    }

    func testInvalidConfigurationFailsWithoutRequest() {
        StubURLProtocol.handler = { _, _ in (200, Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)) }
        let done = expectation(description: "reply")
        var received: Result<String, Error>?
        let task = ChalkGateway(configuration: configuration(key: "short"), session: session()).complete(body: Data("{}".utf8), timeout: 5) { received = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertNil(task)
        XCTAssertThrowsError(try received?.get())
        XCTAssertNil(StubURLProtocol.lastRequest)
    }
}
