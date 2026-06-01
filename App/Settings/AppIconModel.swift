#if os(iOS)
import SwiftUI
import UIKit

/// A selectable app icon. `alternateName` is `nil` for the primary (default) icon;
/// `preview` is the bundled thumbnail image asset shown in the picker.
struct AppIconOption: Identifiable, Sendable {
    let id: String
    let name: String
    let alternateName: String?
    let preview: String
}

enum AppIconCatalog {
    static let options: [AppIconOption] = [
        AppIconOption(id: "default", name: "Blue", alternateName: nil, preview: "Preview-Blue"),
        AppIconOption(id: "AppIcon-Graphite", name: "Graphite", alternateName: "AppIcon-Graphite", preview: "Preview-Graphite"),
        AppIconOption(id: "AppIcon-Indigo", name: "Indigo", alternateName: "AppIcon-Indigo", preview: "Preview-Indigo"),
        AppIconOption(id: "AppIcon-Purple", name: "Purple", alternateName: "AppIcon-Purple", preview: "Preview-Purple"),
        AppIconOption(id: "AppIcon-Teal", name: "Teal", alternateName: "AppIcon-Teal", preview: "Preview-Teal"),
        AppIconOption(id: "AppIcon-Sunset", name: "Sunset", alternateName: "AppIcon-Sunset", preview: "Preview-Sunset"),
        AppIconOption(id: "AppIcon-Iris", name: "Iris", alternateName: "AppIcon-Iris", preview: "Preview-Iris"),
        AppIconOption(id: "AppIcon-Pride", name: "Pride", alternateName: "AppIcon-Pride", preview: "Preview-Pride"),
        AppIconOption(id: "AppIcon-Synthwave", name: "Synthwave", alternateName: "AppIcon-Synthwave", preview: "Preview-Synthwave"),
        AppIconOption(id: "AppIcon-Desert", name: "Desert", alternateName: "AppIcon-Desert", preview: "Preview-Desert"),
        AppIconOption(id: "AppIcon-Aurora", name: "Aurora", alternateName: "AppIcon-Aurora", preview: "Preview-Aurora"),
        AppIconOption(id: "AppIcon-Circuit", name: "Circuit", alternateName: "AppIcon-Circuit", preview: "Preview-Circuit"),
        AppIconOption(id: "AppIcon-Robot", name: "Robot", alternateName: "AppIcon-Robot", preview: "Preview-Robot"),
    ]
}

@MainActor
@Observable
final class AppIconModel {
    private(set) var currentID: String
    var errorMessage: String?

    init() {
        currentID = UIApplication.shared.alternateIconName ?? "default"
    }

    func select(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard UIApplication.shared.alternateIconName != option.alternateName else {
            currentID = option.id
            return
        }
        UIApplication.shared.setAlternateIconName(option.alternateName) { error in
            Task { @MainActor in
                if let error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.currentID = option.id
                }
            }
        }
    }
}
#endif
