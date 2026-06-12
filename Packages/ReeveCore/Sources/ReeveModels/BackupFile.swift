import Foundation

/// A vzdump backup volume from `…/storage/{storage}/content?content=backup`.
public struct BackupFile: Decodable, Sendable, Identifiable, Hashable {
    public let volid: String
    /// Bytes; Int64 to avoid 32-bit overflow on watchOS (arm64_32).
    public let size: Int64?
    public let ctime: Int64?
    public let format: String?
    public let notes: String?
    public let vmid: Int?

    public var id: String { volid }
    public var date: Date? { ctime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    /// The filename portion of the volume id (after the storage and `:`/`/`).
    public var filename: String {
        if let slash = volid.lastIndex(of: "/") {
            return String(volid[volid.index(after: slash)...])
        }
        return volid
    }

    /// Guest type inferred from the volume id (`vzdump-qemu-…` vs `vzdump-lxc-…`).
    public var guestKind: GuestKind? {
        if volid.contains("qemu") || volid.contains("pbs-vm") { return .qemu }
        if volid.contains("lxc") || volid.contains("pbs-ct") { return .lxc }
        return nil
    }
}
