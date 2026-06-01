import ReeveNetworking
import SwiftUI

/// Real service logo from the dashboard-icons CDN (Apache-2.0), with a graceful
/// fall back to the integration's SF Symbol while loading or offline.
struct ServiceLogo: View {
    let typeID: String
    var size: CGFloat = 34

    private var url: URL? {
        URL(string:
            "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/"
            + "\(ServiceCatalogLookup.slug(for: typeID)).png")
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().interpolation(.high).scaledToFit()
            case .empty:
                fallback.redacted(reason: .placeholder)
            default:
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        Image(systemName: ServiceCatalogLookup.symbol(for: typeID))
            .resizable().scaledToFit()
            .foregroundStyle(.tint)
            .padding(size * 0.12)
    }
}
