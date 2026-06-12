#if canImport(CoreSpotlight)
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

/// Index individual guests into Spotlight so they show up (with semantic search)
/// when the user searches the home screen. iOS 18 / macOS 15 feature.
@available(iOS 18.0, macOS 15.0, *)
extension GuestEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .content)
        attrs.title = name
        attrs.contentDescription = "\(serverName) · \(status.label) · \(Int(cpuPercent))% CPU"
        attrs.keywords = [serverName, kind == .container ? "container" : "VM", status.rawValue, "proxmox"]
        return attrs
    }
}

@available(iOS 18.0, macOS 15.0, *)
enum GuestSpotlightIndexer {
    private static let indexedIDsKey = "spotlight.indexedGuestIDs"

    /// Refresh the Spotlight index from the current set of guests, pruning any
    /// guests that no longer exist (deleted VM, removed server, rename) so stale
    /// entries don't linger and then fail when tapped.
    static func reindex() async {
        let guests = await ProxmoxIntentProvider().allGuests()
        let index = CSSearchableIndex.default()
        let current = Set(guests.map(\.id))
        let previous = Set(UserDefaults.standard.stringArray(forKey: indexedIDsKey) ?? [])

        let removed = previous.subtracting(current)
        if !removed.isEmpty {
            try? await index.deleteAppEntities(identifiedBy: Array(removed), ofType: GuestEntity.self)
        }
        if !guests.isEmpty {
            try? await index.indexAppEntities(guests)
        }
        UserDefaults.standard.set(Array(current), forKey: indexedIDsKey)
    }
}
#endif
