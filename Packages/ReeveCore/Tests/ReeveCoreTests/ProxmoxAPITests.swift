import Foundation
import Testing

@testable import ReeveModels
@testable import ReeveNetworking

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let testConnection = ServerConnection(
    baseURL: URL(string: "https://10.0.0.150:8006")!,
    tokenID: "root@pam!homelabapp",
    tokenSecret: "secret-uuid",
    tlsPolicy: .allowInsecure
)

private func makeAPI() -> LiveProxmoxAPI {
    LiveProxmoxAPI(session: MockURLProtocol.session())
}

private func ok(_ json: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(json.utf8))
}

// Serialized because the tests share `MockURLProtocol.handler` (process-global).
@Suite("Proxmox API client", .serialized)
struct ProxmoxAPITests {
    @Test("Sends the PVEAPIToken authorization header without a Bearer prefix")
    func authHeader() async throws {
        MockURLProtocol.handler = { request in
            #expect(
                request.value(forHTTPHeaderField: "Authorization")
                    == "PVEAPIToken=root@pam!homelabapp=secret-uuid"
            )
            return ok(#"{"data":{"version":"9.1.1"}}"#, for: request)
        }
        let version = try await makeAPI().version(testConnection)
        #expect(version.version == "9.1.1")
    }

    @Test("Decodes /cluster/resources into nodes, guests, and storage")
    func clusterResources() async throws {
        let json = """
        {"data":[
          {"id":"node/pve","type":"node","status":"online","node":"pve",
           "cpu":0.0021,"maxcpu":256,"mem":185821626368,"maxmem":270210887680,"uptime":4596679},
          {"id":"lxc/110","type":"lxc","status":"running","node":"pve","name":"jellyfin","vmid":110,
           "cpu":0.05,"maxcpu":12,"mem":273395712,"maxmem":12884901888,"uptime":4591263,
           "netin":150980329369,"netout":80531821808,"tags":"media","template":0},
          {"id":"qemu/107","type":"qemu","status":"running","node":"pve","name":"truenas","vmid":107,
           "cpu":0.0126,"maxcpu":16,"mem":95317450752,"maxmem":103079215104,"uptime":4595938},
          {"id":"storage/pve/local-lvm","type":"storage","status":"available","node":"pve",
           "storage":"local-lvm","plugintype":"lvmthin","disk":469754655539,"maxdisk":1756092170240,"shared":0}
        ]}
        """
        MockURLProtocol.handler = { ok(json, for: $0) }

        let resources = try await makeAPI().clusterResources(testConnection)
        #expect(resources.count == 4)

        let node = try #require(resources.first { $0.type == .node })
        #expect(node.status == .online)
        // cpu fraction -> percent
        #expect(abs((node.cpuPercent ?? 0) - 0.21) < 0.001)

        let guests = resources.filter { $0.type == .qemu || $0.type == .lxc }
        #expect(guests.count == 2)
        let jelly = try #require(resources.first { $0.vmid == 110 })
        #expect(jelly.displayName == "jellyfin")
        #expect(jelly.tagList == ["media"])
        #expect((jelly.memoryFraction ?? 0) > 0)

        let storage = try #require(resources.first { $0.type == .storage })
        #expect(storage.storage == "local-lvm")
    }

    @Test("Decodes per-guest status/current with optional fields")
    func guestStatus() async throws {
        let json = """
        {"data":{"status":"running","name":"jellyfin","vmid":110,"cpu":0.0,"cpus":12,
                 "mem":273395712,"maxmem":12884901888,"uptime":4591879,"netout":80531821808}}
        """
        MockURLProtocol.handler = { ok(json, for: $0) }
        let status = try await makeAPI().guestStatus(
            testConnection, node: "pve", kind: .lxc, vmid: 110
        )
        #expect(status.status == .running)
        #expect(status.cpus == 12)
        #expect(status.disk == nil)
    }

    @Test("RRD points tolerate missing metrics in recent buckets")
    func rrdDecoding() async throws {
        let json = """
        {"data":[
          {"time":1700000000,"cpu":0.1,"mem":1000,"maxmem":2000,"netin":50.0,"netout":10.0},
          {"time":1700000060}
        ]}
        """
        MockURLProtocol.handler = { request in
            #expect(request.url?.query?.contains("timeframe=hour") == true)
            return ok(json, for: request)
        }
        let points = try await makeAPI().guestRRD(
            testConnection, node: "pve", kind: .lxc, vmid: 110, timeframe: .hour
        )
        #expect(points.count == 2)
        #expect(points[0].cpuPercent == 10)
        #expect(points[1].cpu == nil)
    }

    @Test("Power action POSTs to the right path and returns the task UPID")
    func powerAction() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path.hasSuffix("/lxc/110/status/reboot") == true)
            return ok(#"{"data":"UPID:pve:0001:reboot"}"#, for: request)
        }
        let upid = try await makeAPI().power(
            testConnection, node: "pve", kind: .lxc, vmid: 110, action: .reboot
        )
        #expect(upid == "UPID:pve:0001:reboot")
    }

    @Test("Non-2xx responses surface as APIError.badStatus")
    func errorStatus() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"data":null}"#.utf8))
        }
        await #expect(throws: APIError.self) {
            _ = try await makeAPI().clusterResources(testConnection)
        }
    }
}
