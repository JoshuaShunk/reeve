import Foundation
import Testing

@testable import ReeveModels

/// Decoding tests for the management/infrastructure DTOs, including the trickier
/// JSON key mappings (`active-state`, `next-run`, capitalised apt keys, …).
@Suite("Model decoding")
struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func physicalDisk() throws {
        let disk = try decode(PhysicalDisk.self, #"""
        {"devpath":"/dev/nvme0n1","model":"Micron_7400","serial":"x","size":1920383410176,
         "type":"nvme","health":"PASSED","wearout":100,"used":"LVM","vendor":"unknown"}
        """#)
        #expect(disk.id == "/dev/nvme0n1")
        #expect(disk.healthy)
        #expect(disk.size == 1_920_383_410_176)
        #expect(disk.type == "nvme")
    }

    @Test func zfsPoolUsage() throws {
        let pool = try decode(ZFSPool.self, #"{"name":"tank","health":"ONLINE","size":1000,"alloc":250,"free":750}"#)
        #expect(pool.healthy)
        #expect(pool.usedFraction == 0.25)
    }

    @Test func nodeServiceState() throws {
        let svc = try decode(NodeService.self, #"{"name":"pveproxy","desc":"API proxy","state":"running","active-state":"active","unit-state":"enabled"}"#)
        #expect(svc.isRunning)
        #expect(svc.id == "pveproxy")
        let dead = try decode(NodeService.self, #"{"name":"corosync","state":"dead","active-state":"inactive"}"#)
        #expect(!dead.isRunning)
    }

    @Test func aptUpdateKeys() throws {
        let update = try decode(AptUpdate.self, #"{"Package":"dpkg","Title":"pkg mgr","Version":"1.22.22","OldVersion":"1.22.21","Priority":"required"}"#)
        #expect(update.package == "dpkg")
        #expect(update.oldVersion == "1.22.21")
        #expect(update.version == "1.22.22")
    }

    @Test func storageSummary() throws {
        let storage = try decode(StorageSummary.self, #"{"storage":"local","type":"dir","content":"backup,iso","total":1000,"used":150}"#)
        #expect(storage.supportsBackups)
        #expect(storage.usedFraction == 0.15)
    }

    @Test func networkInterface() throws {
        let iface = try decode(NetworkInterface.self, #"{"iface":"vmbr0","type":"bridge","active":1,"cidr":"10.0.0.150/24","gateway":"10.0.0.1","bridge_ports":"nic0"}"#)
        #expect(iface.id == "vmbr0")
        #expect(iface.isActive)
        #expect(iface.bridgePorts == "nic0")
    }

    @Test func replicationJobEnabled() throws {
        #expect(try decode(ReplicationJob.self, #"{"id":"100-0","type":"local","target":"node2","schedule":"*/15"}"#).isEnabled)
        #expect(try !decode(ReplicationJob.self, #"{"id":"100-0","disable":1}"#).isEnabled)
    }

    @Test func backupJobSelection() throws {
        let all = try decode(BackupJob.self, #"{"id":"job1","schedule":"02:00","storage":"local","mode":"snapshot","enabled":1,"all":1,"next-run":1700000000}"#)
        #expect(all.selection == "All guests")
        #expect(all.isEnabled)
        #expect(all.nextRun == 1_700_000_000)
        let some = try decode(BackupJob.self, #"{"id":"job2","vmid":"100,101","enabled":0}"#)
        #expect(some.selection == "100,101")
        #expect(!some.isEnabled)
    }

    @Test func clusterStatus() throws {
        let node = try decode(ClusterStatusEntry.self, #"{"id":"node/pve","name":"pve","type":"node","online":1,"local":1,"ip":"10.0.0.150"}"#)
        #expect(node.isOnline)
        #expect(node.isLocal)
        let cluster = try decode(ClusterStatusEntry.self, #"{"id":"cluster","name":"home","type":"cluster","quorate":1}"#)
        #expect(cluster.quorate == 1)
    }

    @Test func firewallRule() throws {
        let rule = try decode(FirewallRule.self, #"{"pos":0,"type":"in","action":"ACCEPT","enable":1,"proto":"tcp","dport":"8006"}"#)
        #expect(rule.id == 0)
        #expect(rule.isEnabled)
        #expect(rule.action == "ACCEPT")
    }

    @Test func usersAndTokens() throws {
        let user = try decode(PVEUser.self, #"{"userid":"root@pam","enable":1,"email":"x@y.z","realm-type":"pam"}"#)
        #expect(user.id == "root@pam")
        #expect(user.isEnabled)
        #expect(user.realmType == "pam")
        let token = try decode(PVEToken.self, #"{"tokenid":"homelabapp","comment":"app","privsep":1}"#)
        #expect(token.id == "homelabapp")
        #expect(token.privsep == 1)
    }

    @Test func sdn() throws {
        #expect(try decode(SDNZone.self, #"{"zone":"localnet","type":"simple"}"#).id == "localnet")
        #expect(try decode(SDNVNet.self, #"{"vnet":"vnet0","zone":"localnet","tag":100}"#).tag == 100)
    }
}
