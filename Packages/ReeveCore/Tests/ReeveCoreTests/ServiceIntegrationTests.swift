import Foundation
import Testing

@testable import ReeveModels
@testable import ReeveNetworking

/// Returns canned JSON for any request, so integration mapping is tested offline.
private struct StubHTTPClient: HTTPClient {
    let responses: [Data]
    let status: Int
    init(_ responses: [Data], status: Int = 200) {
        self.responses = responses
        self.status = status
    }
    init(_ json: String, status: Int = 200) {
        self.init([Data(json.utf8)], status: status)
    }

    final class Counter: @unchecked Sendable {
        let lock = NSLock(); var index = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; let i = index; index += 1; return i }
    }
    private static let counter = Counter()

    func send(_ request: HTTPRequest, tls: TLSPolicy) async throws -> (Data, HTTPURLResponse) {
        let body = responses[min(Self.counter.next(), responses.count - 1)]
        let response = HTTPURLResponse(
            url: request.url, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }
}

private func instance(typeID: String, config: [String: String] = [:]) -> ServiceInstance {
    ServiceInstance(
        typeID: typeID, name: "Test", baseURLString: "http://10.0.0.2",
        tlsPolicy: .allowInsecure, config: config
    )
}

@Suite("Service integrations")
struct ServiceIntegrationTests {
    @Test("AdGuard maps /control/stats into highlighted stats")
    func adguard() async throws {
        let json = #"{"num_dns_queries":1000,"num_blocked_filtering":250,"avg_processing_time":0.012}"#
        let status = try await AdGuardHomeIntegration().fetchStatus(
            for: instance(typeID: "adguard-home", config: ["username": "admin"]),
            secret: "pw", client: StubHTTPClient(json)
        )
        #expect(status.health == .ok)
        #expect(status.stats.first { $0.id == "block_pct" }?.value == "25.0")
        #expect(status.stats.first { $0.id == "blocked" }?.emphasis == .highlighted)
    }

    @Test("Home Assistant counts entities and flags unavailable")
    func homeAssistant() async throws {
        let json = #"[{"entity_id":"light.a","state":"on"},{"entity_id":"sensor.b","state":"unavailable"}]"#
        let status = try await HomeAssistantIntegration().fetchStatus(
            for: instance(typeID: "home-assistant"), secret: "tok", client: StubHTTPClient(json)
        )
        #expect(status.health == .warn)
        #expect(status.stats.first { $0.id == "entities" }?.value == "2")
        #expect(status.stats.first { $0.id == "unavailable" }?.value == "1")
    }

    @Test("Auth helper builds a Basic header from username + secret")
    func basicAuth() {
        var request = HTTPRequest(url: URL(string: "http://x")!)
        request.applyAuth(.basic(usernameField: "username"), secret: "pw", config: ["username": "admin"])
        // base64("admin:pw") == "YWRtaW46cHc="
        #expect(request.headers["Authorization"] == "Basic YWRtaW46cHc=")
    }

    @Test("Catalog resolves integrations by stable typeID")
    func catalog() {
        #expect(ServiceCatalog.builtIn.integration(for: "adguard-home") != nil)
        #expect(ServiceCatalog.builtIn.integration(for: "nope") == nil)
    }
}
