import Foundation

/// A guest snapshot from `…/{kind}/{vmid}/snapshot`.
public struct Snapshot: Decodable, Sendable, Identifiable, Hashable {
    public let name: String
    public let description: String?
    public let snaptime: Int?
    public let parent: String?
    public let includesRAM: Bool

    public var id: String { name }
    public var isCurrent: Bool { name == "current" }
    public var date: Date? { snaptime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    private enum CodingKeys: String, CodingKey {
        case name, description, snaptime, parent, vmstate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        snaptime = try c.decodeIfPresent(Int.self, forKey: .snaptime)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        // `vmstate` may arrive as 0/1 or true/false depending on PVE version.
        if let intValue = try? c.decode(Int.self, forKey: .vmstate) {
            includesRAM = intValue != 0
        } else if let boolValue = try? c.decode(Bool.self, forKey: .vmstate) {
            includesRAM = boolValue
        } else {
            includesRAM = false
        }
    }

    /// Snapshot names must match `^[A-Za-z][A-Za-z0-9_-]+$` (len ≥ 2) and `current`
    /// is reserved, validate before creating to avoid a 400.
    public static func isValidName(_ name: String) -> Bool {
        guard name != "current", name.count >= 2 else { return false }
        return name.range(of: "^[A-Za-z][A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }
}
