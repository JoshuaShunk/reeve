import SwiftUI
import ReeveModels

/// Per-guest screen: live status, CPU/memory gauges, and power controls.
/// The guest is looked up by id each render so it reflects the latest refresh.
struct GuestDetailView: View {
    let server: WatchServer
    let guestID: String

    @State private var pendingAction: PowerAction?
    @State private var working = false
    @State private var errorMessage: String?

    private var guest: ClusterResource? {
        server.resources.first { $0.id == guestID }
    }

    var body: some View {
        Group {
            if let guest {
                content(for: guest)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(guest?.displayName ?? "Guest")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            pendingAction.map { "\($0.label) this guest?" } ?? "",
            isPresented: confirmationBinding,
            titleVisibility: .visible
        ) {
            if let action = pendingAction {
                Button(action.label, role: action == .start ? nil : .destructive) {
                    perform(action)
                }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        }
    }

    @ViewBuilder
    private func content(for guest: ClusterResource) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                statusHeader(for: guest)

                if guest.status?.isUp == true {
                    HStack(spacing: 16) {
                        MetricGauge(title: "CPU", fraction: guest.cpu)
                        MetricGauge(title: "MEM", fraction: guest.memoryFraction)
                    }
                    Text("Up \(formatUptime(guest.uptime)) · \(formatBytes(guest.mem)) / \(formatBytes(guest.maxmem))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                powerControls(for: guest)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func statusHeader(for guest: ClusterResource) -> some View {
        let isUp = guest.status?.isUp == true
        return HStack(spacing: 8) {
            HealthDot(health: isUp ? .ok : .down)
            Text(isUp ? "Running" : "Stopped")
                .font(.headline)
            Spacer()
            Text(guest.type == .lxc ? "LXC" : "VM")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func powerControls(for guest: ClusterResource) -> some View {
        let isUp = guest.status?.isUp == true
        VStack(spacing: 8) {
            if working {
                ProgressView()
                    .padding(.vertical, 6)
            } else if isUp {
                powerButton(.reboot, tint: .blue)
                powerButton(.shutdown, tint: .orange)
                powerButton(.stop, tint: .red)
            } else {
                powerButton(.start, tint: .green)
            }
        }
    }

    private func powerButton(_ action: PowerAction, tint: Color) -> some View {
        Button {
            errorMessage = nil
            if action.isDisruptive {
                pendingAction = action
            } else {
                perform(action)
            }
        } label: {
            Label(action.label, systemImage: action.symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .controlSize(.large)
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )
    }

    private func perform(_ action: PowerAction) {
        guard let guest else { return }
        pendingAction = nil
        working = true
        errorMessage = nil
        Task {
            do {
                try await server.power(action, on: guest)
            } catch {
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }
}
