import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct AgentView: View {
    @Environment(AppModel.self) private var app
    @State private var model = AgentModel()
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingChatOptions = false
    @State private var editing: ChatMessage?
    @State private var editText = ""
    @FocusState private var inputFocused: Bool
    #if os(iOS)
    @State private var dictation = SpeechDictation()
    @State private var photoItem: PhotosPickerItem?
    #endif

    private static let starters = [
        ("Health check", "Give me a quick health check of my homelab."),
        ("What's stopped?", "Which VMs or containers are stopped?"),
        ("Pending updates", "How many package updates are pending, and on which node?"),
        ("Recent tasks", "Show me the most recent tasks and flag any failures."),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if model.messages.isEmpty { intro } else { transcript }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 18).onChanged { value in
                    if value.translation.height > 30 { inputFocused = false }
                }
            )
            .navigationTitle("Agent")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("History", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                }
                ToolbarItem {
                    Button("New Chat", systemImage: "square.and.pencil") { model.newChat() }
                }
                ToolbarItem {
                    Menu {
                        Button("Chat Instructions", systemImage: "text.badge.star") { showingChatOptions = true }
                        Button("Settings", systemImage: "slider.horizontal.3") { showingSettings = true }
                        if !model.messages.isEmpty {
                            ShareLink("Export Chat", item: exportText)
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let approval = model.pendingApproval { approvalCard(approval) }
                    composer
                }
            }
            .animation(.snappy(duration: 0.22), value: model.pendingApproval?.id)
            .sheet(isPresented: $showingSettings) { AgentSettingsView(store: model.store) }
            .sheet(isPresented: $showingHistory) { ConversationHistoryView(model: model) }
            .sheet(isPresented: $showingChatOptions) { chatOptionsSheet }
            .sheet(item: $editing) { message in editSheet(message) }
            .alert("Agent error", isPresented: .constant(model.error != nil)) {
                Button("Retry") { model.error = nil; model.regenerate(app: app) }
                Button("OK", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
    }

    // MARK: Inline approval

    /// A compact in-flow approval card shown just above the composer, right under
    /// the command the agent wants to run, instead of a detached system popup.
    private func approvalCard(_ approval: ApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(approval.title, systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text(approval.detail)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Spacer()
                Button("Deny") { model.resolveApproval(false) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Approve") { model.resolveApproval(true) }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(.indigo)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.indigo.opacity(0.35)))
        .padding(.horizontal, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Intro

    private var intro: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("AgentBot").resizable().scaledToFit().frame(width: 64, height: 64)
                Text("Reeve Agent").font(.title2.weight(.semibold))
                Text(model.isConfigured
                     ? "Ask about your homelab. It's grounded in your current Proxmox state and can take actions with your approval."
                     : "Connect a local Ollama server or an API key to get started.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if model.isConfigured {
                    VStack(spacing: 8) {
                        ForEach(Self.starters, id: \.0) { starter in
                            Button {
                                model.input = starter.1
                                model.send(app: app)
                            } label: {
                                Text(starter.0)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 11)
                                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Button("Set Up") { showingSettings = true }.glassProminentButton()
                }
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages.filter { $0.role != .system }) { message in
                            MessageBubble(
                                message: message,
                                isLastAssistant: message.id == lastAssistantID,
                                isStreaming: model.isStreaming,
                                onCopy: { copy(message.content) },
                                onRegenerate: { model.regenerate(app: app) },
                                onEdit: { editText = message.content; editing = message }
                            )
                            .id(message.id)
                        }
                        if showThinking {
                            ThinkingIndicator().id("thinking")
                        }
                    }
                    .padding()
                    Color.clear.frame(height: 1).id("bottom")
                        .background(GeometryReader { g in
                            Color.clear.preference(key: BottomKey.self,
                                                   value: g.frame(in: .named("sv")).maxY)
                        })
                }
                .coordinateSpace(name: "sv")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(BottomKey.self) { maxY in
                    atBottom = maxY <= outer.size.height + 100
                }
                .onChange(of: model.messages.last?.content) {
                    if atBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                .onChange(of: model.messages.count) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !atBottom {
                        Button {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.body.weight(.semibold))
                                .padding(10)
                                .background(.regularMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(.quaternary))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scroll to latest")
                        .padding(.trailing, 16).padding(.bottom, 8)
                    }
                }
            }
        }
    }

    @State private var atBottom = true

    private var lastAssistantID: ChatMessage.ID? {
        model.messages.last { $0.role == .assistant }?.id
    }

    private var showThinking: Bool {
        guard model.isStreaming else { return false }
        guard let last = model.messages.last else { return true }
        return last.role != .assistant || last.content.isEmpty
    }

    // MARK: Composer

    private var canSend: Bool {
        !model.input.trimmingCharacters(in: .whitespaces).isEmpty || model.pendingImage != nil
    }

    private var composer: some View {
        VStack(spacing: 8) {
            #if os(iOS)
            if let b64 = model.pendingImage, let data = Data(base64Encoded: b64),
               let ui = UIImage(data: data) {
                HStack {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button { model.pendingImage = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
            #endif
            HStack(alignment: .bottom, spacing: 8) {
                #if os(iOS)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Attach image")
                .padding(.bottom, 3)
                #endif

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Message", text: $model.input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .padding(.leading, 16)
                        .padding(.vertical, 10)
                        .focused($inputFocused)

                    #if os(iOS)
                    Button {
                        Task { await dictation.toggle() }
                    } label: {
                        Image(systemName: dictation.state == .listening ? "mic.fill" : "mic")
                            .font(.system(size: 20))
                            .foregroundStyle(dictation.state == .listening ? Color.red : Color.secondary)
                            .padding(.bottom, 9)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.state == .listening ? "Stop dictation" : "Dictate")
                    .onChange(of: dictation.transcript) { _, text in
                        if dictation.state == .listening, !text.isEmpty { model.input = text }
                    }
                    #endif

                    Button {
                        if model.isStreaming { model.stop() } else { model.send(app: app) }
                    } label: {
                        Image(systemName: model.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle((model.isStreaming || canSend) ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.isStreaming ? "Stop" : "Send")
                    .disabled(!model.isStreaming && !canSend)
                    .padding(.trailing, 6).padding(.bottom, 5)
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.background.secondary)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.quaternary, lineWidth: 1))
                )
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        #if os(iOS)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.pendingImage = Self.downscaledJPEGBase64(data, maxDimension: 1024)
                }
                photoItem = nil
            }
        }
        #endif
    }

    #if os(iOS)
    private static func downscaledJPEGBase64(_ data: Data, maxDimension: CGFloat) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let jpeg = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.7) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return jpeg.base64EncodedString()
    }
    #endif

    // MARK: Edit sheet

    private func editSheet(_ message: ChatMessage) -> some View {
        NavigationStack {
            Form {
                TextField("Message", text: $editText, axis: .vertical).lineLimit(3...12)
            }
            .navigationTitle("Edit Message")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        model.editAndResend(message, text: editText, app: app)
                        editing = nil
                    }
                }
            }
        }
    }

    private var chatOptionsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Custom instructions", text: $model.instructions, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Instructions for this chat")
                } footer: {
                    Text("Added to the system prompt for this conversation only (e.g. \u{201C}always answer in bullet points\u{201D}).")
                }
                Section {
                    TextField("Model override (optional)", text: $model.modelOverride)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                } footer: {
                    Text("Use a different model for this chat. Leave blank to use the default from Settings.")
                }
            }
            .navigationTitle("Chat Instructions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showingChatOptions = false } }
            }
        }
    }

    // MARK: Helpers

    private var exportText: String {
        model.messages.filter { $0.role == .user || $0.role == .assistant }
            .map { "\($0.role == .user ? "You" : "Agent"):\n\($0.content)" }
            .joined(separator: "\n\n")
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct BottomKey: SwiftUI.PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Thinking indicator

private struct ThinkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().frame(width: 7, height: 7)
                    .opacity(phase == Double(i) ? 1 : 0.3)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Thinking")
        .onAppear {
            // Respect Reduce Motion: leave the dots static rather than looping.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) { phase = 2 }
        }
    }
}

// MARK: - Message rendering

private struct MessageBubble: View {
    let message: ChatMessage
    let isLastAssistant: Bool
    let isStreaming: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void

    var body: some View {
        switch message.role {
        case .tool:
            ToolRow(message: message)
        case .user:
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 6) {
                    #if os(iOS)
                    if let b64 = message.imageBase64, let data = Data(base64Encoded: b64),
                       let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    #endif
                    if !message.content.isEmpty {
                        Text(userRendered)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                }
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc", action: onCopy)
                    Button("Edit", systemImage: "pencil", action: onEdit)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    ReasoningView(text: reasoning)
                }
                if message.content.isEmpty {
                    if !isStreaming { Text("…").foregroundStyle(.secondary) }
                } else {
                    MarkdownView(text: message.content).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc", action: onCopy)
                if isLastAssistant {
                    Button("Regenerate", systemImage: "arrow.clockwise", action: onRegenerate)
                }
            }
        }
    }

    private var userRendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.content, options: options)) ?? AttributedString(message.content)
    }
}

private struct ReasoningView: View {
    let text: String
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(text).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Thinking", systemImage: "brain").font(.caption).foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }
}

/// A single agent step (tool call). Rendered icon-free as ambient activity: a
/// muted one-liner in a left "gutter" rule, tappable to reveal a monospaced
/// args/result block. The gutter rule, not an icon, signals "system activity".
private struct ToolRow: View {
    let message: ChatMessage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var detail: String? {
        let d = message.detail ?? ""
        return d.isEmpty ? nil : d
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                guard detail != nil else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.content)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if detail != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(detail == nil)

            if expanded, let detail {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Capsule().fill(.secondary.opacity(0.25)).frame(width: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.content)
        .accessibilityValue(detail == nil ? "" : (expanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(detail == nil ? "" : "Double-tap to toggle details")
    }
}

// MARK: - History

private struct ConversationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AgentModel
    @State private var query = ""
    @State private var renaming: Conversation?
    @State private var newTitle = ""

    private var filtered: [Conversation] {
        guard !query.isEmpty else { return model.conversations }
        return model.conversations.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.conversations.isEmpty {
                    ContentUnavailableView("No History", systemImage: "clock",
                                           description: Text("Your past conversations will appear here."))
                }
                ForEach(filtered) { conversation in
                    Button {
                        model.select(conversation); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.title).foregroundStyle(.primary).lineLimit(1)
                            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Rename", systemImage: "pencil") {
                            newTitle = conversation.title; renaming = conversation
                        }.tint(.blue)
                    }
                }
                .onDelete { $0.map { filtered[$0] }.forEach(model.delete) }
            }
            .searchable(text: $query, prompt: "Search chats")
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) {
                    Button("New Chat", systemImage: "square.and.pencil") { model.newChat(); dismiss() }
                }
            }
            .alert("Rename Chat", isPresented: .constant(renaming != nil)) {
                TextField("Title", text: $newTitle)
                Button("Save") {
                    if let c = renaming { model.rename(c, to: newTitle) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }
}

// MARK: - Settings

private struct AgentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AgentConfigStore

    @State private var config = AgentConfig()
    @State private var apiKey = ""
    @State private var models: [String] = []
    @State private var status: String?
    @State private var loading = false
    @State private var searchKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $config.mode) {
                        ForEach(AgentMode.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Base URL", text: $config.baseURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        #endif
                    if config.mode == .openAICompatible {
                        SecureField("API key", text: $apiKey)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text(config.mode == .ollama
                         ? "e.g. http://10.0.0.50:11434, your Ollama host on the LAN."
                         : "e.g. https://api.openai.com/v1 (OpenAI), or any compatible endpoint. The key is stored in the Keychain.")
                }

                Section {
                    Toggle("Allow actions", isOn: $config.allowActions)
                    if config.allowActions {
                        Toggle("Auto-run guest commands", isOn: $config.autoApproveShell)
                    }
                } footer: {
                    Text(config.allowActions && config.autoApproveShell
                        ? "Lets the agent run tools to read and control your homelab. Shell commands inside guests run WITHOUT a per-command prompt, convenient for unattended setups, but it can run any root command. Other state-changing actions still ask first."
                        : "Lets the agent run tools to read and control your homelab. State-changing actions always ask for your approval first.")
                }

                Section {
                    Picker("Search provider", selection: $config.searchProvider) {
                        ForEach(SearchProvider.allCases) { Text($0.label).tag($0) }
                    }
                    if config.searchProvider.needsInstanceURL {
                        TextField("SearXNG URL", text: $config.searxngURL)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            #endif
                    }
                    if config.searchProvider.needsAPIKey {
                        SecureField("API key", text: $searchKey)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                    }
                } header: {
                    Text("Web search")
                } footer: {
                    Text(searchFooter)
                }

                Section("Model") {
                    if models.isEmpty {
                        TextField("Model name", text: $config.model)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                    } else {
                        Picker("Model", selection: $config.model) {
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button {
                        Task { await loadModels() }
                    } label: {
                        HStack { Text("Fetch models"); Spacer(); if loading { ProgressView() } }
                    }
                    .disabled(loading)
                    if let status {
                        Text(status).font(.caption)
                            .foregroundStyle(status.hasPrefix("Found") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Agent Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                config = store.config
                apiKey = store.apiKey ?? ""
                searchKey = store.searchAPIKey ?? ""
            }
        }
    }

    private func loadModels() async {
        loading = true; defer { loading = false }
        if config.mode == .openAICompatible, !apiKey.isEmpty { store.setAPIKey(apiKey) }
        do {
            let found = try await AgentClient().listModels(config: config, apiKey: apiKey)
            models = found
            status = found.isEmpty ? "No models found" : "Found \(found.count) models"
            if config.model.isEmpty { config.model = found.first ?? "" }
        } catch {
            status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() {
        store.config = config
        if config.mode == .openAICompatible, !apiKey.isEmpty { store.setAPIKey(apiKey) }
        if config.searchProvider.needsAPIKey, !searchKey.isEmpty { store.setSearchAPIKey(searchKey) }
        dismiss()
    }

    private var searchFooter: String {
        switch config.searchProvider {
        case .duckDuckGo:
            "Lets the agent search the web. DuckDuckGo needs no key, brief instant answers, with a Wikipedia fallback for general queries."
        case .searxng:
            "Point at your own SearXNG instance for full web results, no third-party key. Enable `json` in your instance's search.formats."
        case .tavily:
            "Tavily is tuned for AI and returns a synthesized answer plus sources. Free tier available; the key is stored in the Keychain."
        case .brave:
            "Brave Search has an independent index. Free tier available; the key is stored in the Keychain."
        }
    }
}
