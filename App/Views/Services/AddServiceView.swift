import ReeveModels
import ReeveNetworking
import SwiftUI

/// A view-facing descriptor of a service *type*, derived from the catalog.
private struct ServiceTypeInfo: Identifiable, Hashable {
    let id: String          // typeID
    let name: String
    let symbol: String
    let category: ServiceCategory

    static var all: [ServiceTypeInfo] {
        ServiceCatalog.builtIn.integrations.map {
            ServiceTypeInfo(
                id: type(of: $0).typeID,
                name: $0.displayName,
                symbol: $0.iconAsset.systemName,
                category: $0.category
            )
        }
    }
}

/// Step 1: pick a service type, grouped by category. Step 2: a generic config
/// form generated from the integration's declared `configFields`.
struct AddServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ServiceCategory.allCases, id: \.self) { category in
                    let items = ServiceTypeInfo.all.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(category.label) {
                            ForEach(items) { info in
                                NavigationLink(value: info.id) {
                                    HStack(spacing: 12) {
                                        ServiceLogo(typeID: info.id, size: 28)
                                        Text(info.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Service")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { typeID in
                ServiceConfigForm(typeID: typeID, onSaved: { dismiss() })
            }
        }
    }
}

private struct ServiceConfigForm: View {
    @Environment(AppModel.self) private var app
    let typeID: String
    let onSaved: () -> Void

    @State private var name = ""
    @State private var urlString = ""
    @State private var allowInsecure = true
    @State private var secret = ""
    @State private var config: [String: String] = [:]

    private var integration: (any ServiceIntegration)? {
        ServiceCatalog.builtIn.integration(for: typeID)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Server URL", text: $urlString)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    #endif
                Toggle("Allow self-signed certificate", isOn: $allowInsecure)
            } footer: {
                Text("e.g. http://10.0.0.2 or https://service.example.com")
            }

            if let integration {
                if !integration.configFields.isEmpty {
                    Section {
                        ForEach(integration.configFields) { field in
                            configControl(for: field)
                        }
                    }
                }
                if integration.authMethod.needsSecret {
                    Section {
                        SecureField(integration.authMethod.secretLabel, text: $secret)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    } header: {
                        Text("Authentication")
                    }
                }
            }
        }
        .navigationTitle(integration?.displayName ?? "Service")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { save() }.disabled(!canSave)
            }
        }
        .onAppear {
            if name.isEmpty { name = integration?.displayName ?? "" }
        }
    }

    @ViewBuilder private func configControl(for field: ConfigField) -> some View {
        let binding = Binding(
            get: { config[field.key] ?? field.defaultValue ?? "" },
            set: { config[field.key] = $0 }
        )
        switch field.kind {
        case .toggle:
            Toggle(field.label, isOn: Binding(
                get: { (config[field.key] ?? "false") == "true" },
                set: { config[field.key] = $0 ? "true" : "false" }
            ))
        case .secret:
            SecureField(field.label, text: binding)
        default:
            TextField(field.placeholder ?? field.label, text: binding)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
        }
    }

    private var canSave: Bool {
        guard !name.isEmpty, !urlString.isEmpty, let integration else { return false }
        if integration.authMethod.needsSecret && secret.isEmpty { return false }
        for field in integration.configFields where field.isRequired {
            if (config[field.key] ?? "").isEmpty { return false }
        }
        return true
    }

    private func save() {
        let instance = ServiceInstance(
            typeID: typeID,
            name: name,
            baseURLString: urlString,
            tlsPolicy: allowInsecure ? .allowInsecure : .system,
            config: config
        )
        try? app.serviceStore.save(instance, secret: secret.isEmpty ? nil : secret)
        onSaved()
    }
}
