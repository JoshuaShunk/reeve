import SwiftUI

struct NotificationChannelsView: View {
    @State private var channels: [NotificationChannel] = []
    @State private var editing: NotificationChannel?
    @State private var showingAdd = false
    private let store = ChannelStore()

    var body: some View {
        List {
            Section {
                ForEach(channels) { channel in
                    Button {
                        editing = channel
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: channel.kind.symbol)
                                .frame(width: 24).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name).foregroundStyle(.primary)
                                Text(channel.kind.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !channel.enabled {
                                Text("Off").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { channels.remove(atOffsets: $0); store.save(channels) }
            } footer: {
                Text("Alerts (high CPU/memory, guest down, task finished) are also sent to every enabled channel, so they reach you when the app is closed.")
            }
        }
        .navigationTitle("Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem { Button("Add", systemImage: "plus") { showingAdd = true } }
        }
        .sheet(isPresented: $showingAdd) {
            ChannelEditor(channel: NotificationChannel(kind: .discord, name: "Discord")) { saved in
                channels.append(saved); store.save(channels)
            }
        }
        .sheet(item: $editing) { channel in
            ChannelEditor(channel: channel) { saved in
                if let i = channels.firstIndex(where: { $0.id == saved.id }) { channels[i] = saved }
                store.save(channels)
            }
        }
        .onAppear { channels = store.load() }
    }
}

private struct ChannelEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var channel: NotificationChannel
    var onSave: (NotificationChannel) -> Void

    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Service", selection: $channel.kind) {
                        ForEach(NotificationChannel.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Name", text: $channel.name)
                    Toggle("Enabled", isOn: $channel.enabled)
                }

                Section {
                    if channel.kind == .telegram {
                        TextField("Bot token", text: $channel.botToken)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                        TextField("Chat ID", text: $channel.chatID)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                    } else {
                        TextField("Webhook URL", text: $channel.url)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                            #endif
                    }
                } header: {
                    Text(channel.kind.label)
                } footer: {
                    Text(hint)
                }

                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Text("Send Test")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || !isValid)
                    if let testResult {
                        Text(testResult).font(.caption)
                            .foregroundStyle(testResult.hasPrefix("Sent") ? .green : .red)
                    }
                }
            }
            .navigationTitle(channel.name.isEmpty ? "Channel" : channel.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(channel); dismiss() }.disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        if channel.name.isEmpty { return false }
        return channel.kind == .telegram
            ? (!channel.botToken.isEmpty && !channel.chatID.isEmpty)
            : !channel.url.isEmpty
    }

    private var hint: String {
        switch channel.kind {
        case .discord: "Server Settings → Integrations → Webhooks → New Webhook → Copy URL."
        case .slack: "Create an Incoming Webhook in your Slack app settings."
        case .telegram: "Message @BotFather to make a bot; get the chat ID from @userinfobot."
        case .webhook: "Any endpoint that accepts a JSON POST of { title, body }."
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        do { try await WebhookNotifier.test(channel); testResult = "Sent ✅" }
        catch { testResult = "Failed: \(error.localizedDescription)" }
    }
}
