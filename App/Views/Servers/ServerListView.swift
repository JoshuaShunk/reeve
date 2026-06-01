import ReevePersistence
import SwiftUI

/// Manage saved servers: pick the active one, add, or delete.
struct ServerListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false

    var body: some View {
        List {
            ForEach(app.profiles.profiles) { profile in
                Button {
                    app.profiles.selectedID = profile.id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name)
                            Text(profile.baseURL?.absoluteString ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.id == app.profiles.selectedID {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                for index in indexSet { app.profiles.delete(app.profiles.profiles[index]) }
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem { Button("Add", systemImage: "plus") { showingAdd = true } }
        }
        .sheet(isPresented: $showingAdd) {
            AddServerView()
        }
    }
}
