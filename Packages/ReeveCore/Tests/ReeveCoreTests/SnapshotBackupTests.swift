import Foundation
import Testing

@testable import ReeveModels

@Suite("Snapshots, backups, tasks")
struct SnapshotBackupTests {
    @Test("Decodes snapshot list incl. vmstate as int or bool")
    func snapshots() throws {
        let json = """
        [{"name":"current","description":"You are here!"},
         {"name":"before-update","snaptime":1700000000,"description":"pre","parent":"base","vmstate":1},
         {"name":"base","snaptime":1690000000,"vmstate":false}]
        """
        let snaps = try JSONDecoder().decode([Snapshot].self, from: Data(json.utf8))
        #expect(snaps.count == 3)
        let current = try #require(snaps.first { $0.name == "current" })
        #expect(current.isCurrent)
        let before = try #require(snaps.first { $0.name == "before-update" })
        #expect(before.includesRAM)
        #expect(before.parent == "base")
        #expect(snaps.first { $0.name == "base" }?.includesRAM == false)
    }

    @Test("Validates snapshot names")
    func names() {
        #expect(Snapshot.isValidName("before-update_2"))
        #expect(!Snapshot.isValidName("current"))      // reserved
        #expect(!Snapshot.isValidName("1abc"))         // leading digit
        #expect(!Snapshot.isValidName("a"))            // too short
        #expect(!Snapshot.isValidName("has space"))
    }

    @Test("Decodes backup content and infers guest kind")
    func backups() throws {
        let json = """
        [{"volid":"local:backup/vzdump-qemu-107-2026_05_29-03_00_01.vma.zst",
          "size":1073741824,"ctime":1716950401,"format":"vma.zst","vmid":107,"notes":"weekly"},
         {"volid":"local:backup/vzdump-lxc-110-2026_05_28.tar.zst","size":500,"vmid":110}]
        """
        let backups = try JSONDecoder().decode([BackupFile].self, from: Data(json.utf8))
        #expect(backups.count == 2)
        #expect(backups[0].guestKind == .qemu)
        #expect(backups[0].filename == "vzdump-qemu-107-2026_05_29-03_00_01.vma.zst")
        #expect(backups[1].guestKind == .lxc)
    }

    @Test("Task list row uses `status` (no exitstatus) for outcome")
    func taskListRows() throws {
        let json = """
        [{"upid":"UPID:pve:1:2:3:aptupdate::root@pam:","type":"aptupdate","id":"","user":"root@pam",
          "status":"OK","starttime":1716950401,"endtime":1716950460},
         {"upid":"UPID:pve:4:5:6:vzdump:107:root@pam:","type":"vzdump","id":"107","user":"root@pam",
          "status":"running","starttime":1716950500}]
        """
        let rows = try JSONDecoder().decode([ProxmoxTaskInfo].self, from: Data(json.utf8))
        let done = try #require(rows.first { $0.type == "aptupdate" })
        #expect(!done.isRunning)
        #expect(done.succeeded)           // from status="OK", though exitstatus is absent
        #expect(done.displayStatus == "OK")
        let running = try #require(rows.first { $0.type == "vzdump" })
        #expect(running.isRunning)
        #expect(running.workerID == "107")
    }

    @Test("Node RRD memory keys (memused/memtotal) feed memoryUsedBytes")
    func nodeRRDMemory() throws {
        let nodePoint = try JSONDecoder().decode(
            RRDPoint.self,
            from: Data(#"{"time":1700000000,"cpu":0.07,"memused":1000,"memtotal":2000}"#.utf8))
        #expect(nodePoint.memoryUsedBytes == 1000)
        let guestPoint = try JSONDecoder().decode(
            RRDPoint.self,
            from: Data(#"{"time":1700000000,"cpu":0.07,"mem":500,"maxmem":2000}"#.utf8))
        #expect(guestPoint.memoryUsedBytes == 500)
    }

    @Test("Parses UPID node and task success/failure")
    func tasks() throws {
        let upid = try #require(UPID("UPID:pve:00002F9D:000DC5EA:57500527:vzdump:107:root@pam!homelabapp:"))
        #expect(upid.node == "pve")

        let ok = try JSONDecoder().decode(
            ProxmoxTaskStatus.self,
            from: Data(#"{"status":"stopped","exitstatus":"OK","type":"qmsnapshot"}"#.utf8))
        #expect(ok.succeeded)
        let fail = try JSONDecoder().decode(
            ProxmoxTaskStatus.self,
            from: Data(#"{"status":"stopped","exitstatus":"command failed","type":"qmrollback"}"#.utf8))
        #expect(!fail.succeeded)
        #expect(fail.failureMessage == "command failed")
    }
}
