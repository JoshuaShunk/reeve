import Foundation
import Testing

@testable import ReeveModels
@testable import ReeveNetworking

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let conn = ServerConnection(
    baseURL: URL(string: "https://host:8006")!,
    tokenID: "u@pam!t", tokenSecret: "s", tlsPolicy: .allowInsecure
)

private func makeAPI() -> LiveProxmoxAPI { LiveProxmoxAPI(session: MockURLProtocol.session()) }

private func ok(_ json: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                     headerFields: ["Content-Type": "application/json"])!, Data(json.utf8))
}

/// Verifies the HTTP method, path, and query the client builds for the
/// management endpoints. Declared as an extension of `ProxmoxAPITests` so these
/// share that suite's `.serialized` trait, the mock handler is process-global.
extension ProxmoxAPITests {

    @Test func cloneGuest() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/nodes/pve/qemu/106/clone"))
            let q = req.url!.query ?? ""
            #expect(q.contains("newid=108"))
            #expect(q.contains("full=1"))
            return ok(#"{"data":"UPID:pve:clone"}"#, for: req)
        }
        let upid = try await makeAPI().cloneGuest(conn, node: "pve", kind: .qemu, vmid: 106,
                                                  newID: 108, name: "copy", full: true, targetStorage: nil)
        #expect(upid.hasPrefix("UPID"))
    }

    @Test func deleteGuestPurge() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "DELETE")
            #expect(req.url!.path.hasSuffix("/nodes/pve/lxc/103"))
            #expect((req.url!.query ?? "").contains("purge=1"))
            return ok(#"{"data":"UPID:pve:destroy"}"#, for: req)
        }
        _ = try await makeAPI().deleteGuest(conn, node: "pve", kind: .lxc, vmid: 103, purge: true)
    }

    @Test func migrateGuestQemuOnline() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/nodes/pve/qemu/106/migrate"))
            let q = req.url!.query ?? ""
            #expect(q.contains("target=node2"))
            #expect(q.contains("online=1"))
            return ok(#"{"data":"UPID:pve:migrate"}"#, for: req)
        }
        _ = try await makeAPI().migrateGuest(conn, node: "pve", kind: .qemu, vmid: 106, target: "node2", online: true)
    }

    @Test func updateConfigUsesPUT() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "PUT")
            #expect(req.url!.path.hasSuffix("/nodes/pve/lxc/103/config"))
            let q = req.url!.query ?? ""
            #expect(q.contains("cores=2"))
            #expect(q.contains("memory=2048"))
            return ok(#"{"data":null}"#, for: req)
        }
        try await makeAPI().updateGuestConfig(conn, node: "pve", kind: .lxc, vmid: 103,
                                              parameters: ["cores": "2", "memory": "2048"])
    }

    @Test func resizeDiskUsesPUT() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "PUT")
            #expect(req.url!.path.hasSuffix("/nodes/pve/qemu/106/resize"))
            let q = req.url!.query ?? ""
            #expect(q.contains("disk=scsi0"))
            #expect(q.contains("size=%2B8G") || q.contains("size=+8G"))
            return ok(#"{"data":"UPID:pve:resize"}"#, for: req)
        }
        _ = try await makeAPI().resizeDisk(conn, node: "pve", kind: .qemu, vmid: 106, disk: "scsi0", size: "+8G")
    }

    @Test func nextID() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.url!.path.hasSuffix("/cluster/nextid"))
            return ok(#"{"data":"108"}"#, for: req)
        }
        #expect(try await makeAPI().nextID(conn) == 108)
    }

    @Test func nodeCommand() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/nodes/pve/status"))
            #expect((req.url!.query ?? "").contains("command=reboot"))
            return ok(#"{"data":"UPID:pve:reboot"}"#, for: req)
        }
        _ = try await makeAPI().nodeCommand(conn, node: "pve", command: "reboot")
    }

    @Test func wakeOnLAN() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/nodes/pve/wakeonlan"))
            return ok(#"{"data":"AA:BB:CC:DD:EE:FF"}"#, for: req)
        }
        _ = try await makeAPI().wakeOnLAN(conn, node: "pve")
    }

    @Test func serviceAction() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/nodes/pve/services/pveproxy/restart"))
            return ok(#"{"data":"UPID:pve:srvrestart"}"#, for: req)
        }
        _ = try await makeAPI().serviceAction(conn, node: "pve", service: "pveproxy", action: "restart")
    }

    @Test func createBackup() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/nodes/pve/vzdump"))
            let q = req.url!.query ?? ""
            #expect(q.contains("vmid=106"))
            #expect(q.contains("storage=local"))
            #expect(q.contains("mode=snapshot"))
            return ok(#"{"data":"UPID:pve:vzdump"}"#, for: req)
        }
        _ = try await makeAPI().createBackup(conn, node: "pve", vmid: 106, storage: "local",
                                            mode: "snapshot", compress: "zstd", removeOld: true)
    }

    @Test func restoreBackupQemuVsLxc() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/nodes/pve/qemu"))
            #expect((req.url!.query ?? "").contains("archive="))
            return ok(#"{"data":"UPID:pve:restore"}"#, for: req)
        }
        _ = try await makeAPI().restoreBackup(conn, node: "pve", kind: .qemu, vmid: 106,
                                             archive: "local:backup/vzdump-qemu-106.vma.zst", storage: nil, force: false)

        MockURLProtocol.handler = { req in
            #expect(req.url!.path.hasSuffix("/nodes/pve/lxc"))
            let q = req.url!.query ?? ""
            #expect(q.contains("ostemplate="))
            #expect(q.contains("restore=1"))
            return ok(#"{"data":"UPID:pve:restore"}"#, for: req)
        }
        _ = try await makeAPI().restoreBackup(conn, node: "pve", kind: .lxc, vmid: 103,
                                             archive: "local:backup/vzdump-lxc-103.tar.zst", storage: nil, force: true)
    }

    @Test func createGuest() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/nodes/pve/lxc"))
            #expect((req.url!.query ?? "").contains("vmid=110"))
            return ok(#"{"data":"UPID:pve:create"}"#, for: req)
        }
        _ = try await makeAPI().createGuest(conn, node: "pve", kind: .lxc,
                                           parameters: ["vmid": "110", "ostemplate": "local:vztmpl/debian.tar.zst"])
    }

    @Test func firewallRuleCRUD() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/cluster/firewall/rules"))
            return ok(#"{"data":null}"#, for: req)
        }
        try await makeAPI().createFirewallRule(conn, basePath: "cluster/firewall",
                                               parameters: ["type": "in", "action": "ACCEPT"])

        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "PUT")
            #expect(req.url!.path.hasSuffix("/cluster/firewall/rules/3"))
            #expect((req.url!.query ?? "").contains("enable=0"))
            return ok(#"{"data":null}"#, for: req)
        }
        try await makeAPI().updateFirewallRule(conn, basePath: "cluster/firewall", pos: 3, parameters: ["enable": "0"])

        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "DELETE")
            #expect(req.url!.path.hasSuffix("/cluster/firewall/rules/3"))
            return ok(#"{"data":null}"#, for: req)
        }
        try await makeAPI().deleteFirewallRule(conn, basePath: "cluster/firewall", pos: 3)
    }

    @Test func backupJobCRUD() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url!.path.hasSuffix("/cluster/backup"))
            #expect((req.url!.query ?? "").contains("schedule="))
            return ok(#"{"data":null}"#, for: req)
        }
        try await makeAPI().createBackupJob(conn, parameters: ["storage": "local", "schedule": "02:00"])

        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "PUT")
            #expect(req.url!.path.hasSuffix("/cluster/backup/job-1"))
            return ok(#"{"data":null}"#, for: req)
        }
        try await makeAPI().updateBackupJob(conn, id: "job-1", parameters: ["enabled": "0"])

        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "DELETE")
            #expect(req.url!.path.hasSuffix("/cluster/backup/job-1"))
            return ok(#"{"data":null}"#, for: req)
        }
        try await makeAPI().deleteBackupJob(conn, id: "job-1")
    }

    @Test func readsDecodeArrays() async throws {
        MockURLProtocol.handler = { req in
            #expect(req.url!.path.hasSuffix("/nodes/pve/disks/list"))
            return ok(#"{"data":[{"devpath":"/dev/sda","health":"PASSED","size":1000,"type":"ssd"}]}"#, for: req)
        }
        let disks = try await makeAPI().physicalDisks(conn, node: "pve")
        #expect(disks.count == 1)
        #expect(disks.first?.healthy == true)
    }
}
