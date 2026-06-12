import AppIntents
import ReeveModels
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(PreferenceKey.biometricLock) private var biometricLock = false
    @AppStorage(PreferenceKey.refreshInterval) private var refreshInterval = 5.0
    @AppStorage(PreferenceKey.defaultTimeframe) private var defaultTimeframe = RRDTimeframe.hour.rawValue
    @AppStorage(PreferenceKey.alertsEnabled) private var alertsEnabled = false
    @AppStorage(PreferenceKey.cpuThreshold) private var cpuThreshold = 0.0
    @AppStorage(PreferenceKey.memThreshold) private var memThreshold = 90.0
    @AppStorage(PreferenceKey.tempThreshold) private var tempThreshold = 0.0
    @AppStorage(PreferenceKey.notifyGuestDown) private var notifyGuestDown = true
    @AppStorage(PreferenceKey.notifyTaskComplete) private var notifyTaskComplete = true
    @AppStorage(PreferenceKey.liveActivitiesEnabled) private var liveActivitiesEnabled = false
    #if os(iOS)
    @State private var iconModel = AppIconModel()
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Require Face ID / Passcode", isOn: $biometricLock)
                } header: {
                    Text("Security")
                } footer: {
                    Text("Lock the app behind biometrics when it goes to the background.")
                }

                Section("Dashboard") {
                    Picker("Refresh every", selection: $refreshInterval) {
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                    }
                    Picker("Default chart range", selection: $defaultTimeframe) {
                        ForEach(RRDTimeframe.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }

                #if os(iOS)
                Section("App Icon") {
                    appIconPicker
                }
                #endif

                Section {
                    Toggle("Enable alerts", isOn: $alertsEnabled)
                        .onChange(of: alertsEnabled) {
                            if alertsEnabled {
                                Task { await AlertCenter.shared.requestAuthorizationIfNeeded() }
                            }
                        }
                    if alertsEnabled {
                        thresholdRow("CPU usage", value: $cpuThreshold)
                        thresholdRow("Memory usage", value: $memThreshold)
                        thresholdRow("Temperature", value: $tempThreshold,
                                     range: 0...110, step: 5, unit: "°C")
                        Toggle("Notify when a guest goes down", isOn: $notifyGuestDown)
                        Toggle("Notify when a task finishes", isOn: $notifyTaskComplete)
                    }
                    #if os(iOS)
                    Toggle("Show running tasks as Live Activities", isOn: $liveActivitiesEnabled)
                    #endif
                    NavigationLink {
                        NotificationChannelsView()
                    } label: {
                        Label("Notification Channels", systemImage: "bell.badge")
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("Background checks are best-effort; iOS controls how often they run. A threshold of 0% is off.")
                }

                #if os(iOS)
                Section {
                    SiriTipView(intent: HomelabStatusIntent())
                    ShortcutsLink()
                } header: {
                    Text("Siri & Shortcuts")
                } footer: {
                    Text("Say things like \u{201C}Homelab status\u{201D} or \u{201C}Start [guest] in Reeve.\u{201D} Tap to add or customize phrases in the Shortcuts app.")
                }
                #endif

                Section {
                    LabeledContent("Version", value: appVersion)
                    Link(destination: URL(string: "https://github.com/joshuashunk/reeve")!) {
                        Label("GitHub", systemImage: "link")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Service logos from dashboard-icons (Apache-2.0).")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func thresholdRow(
        _ label: String, value: Binding<Double>,
        range: ClosedRange<Double> = 0...100, step: Double = 5, unit: String = "%"
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue == 0 ? "Off" : "\(Int(value.wrappedValue))\(unit)")
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    #if os(iOS)
    private var appIconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(AppIconCatalog.options) { option in
                    Button { iconModel.select(option) } label: {
                        VStack(spacing: 6) {
                            iconSwatch(option)
                            Text(option.name)
                                .font(.caption2)
                                .foregroundStyle(iconModel.currentID == option.id ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func iconSwatch(_ option: AppIconOption) -> some View {
        let selected = iconModel.currentID == option.id
        return Image(option.preview)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.1),
                                  lineWidth: selected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 6, y: -6)
                }
            }
    }
    #endif
}

/// Full-screen lock shown when biometric lock is enabled and the app is locked.
struct LockView: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Reeve is locked").font(.headline)
                Button("Unlock") { Task { await lock.authenticate() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .task { await lock.authenticate() }
    }
}
