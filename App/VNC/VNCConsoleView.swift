#if os(iOS)
import ReeveModels
import ReevePersistence
import SwiftUI
import UIKit

/// A graphical (VNC) console for a QEMU virtual machine. Fetches a one-time
/// `vncproxy` ticket, connects over RFB, renders the live framebuffer, and maps
/// touches to pointer events plus an on-screen keyboard for typing.
struct VNCConsoleView: View {
    @Environment(AppModel.self) private var app
    let guest: ClusterResource
    let profile: ServerProfile

    @State private var session: VNCConnection?
    @State private var setupError: String?
    @State private var keyboardActive = false

    var body: some View {
        Group {
            if let setupError {
                ContentUnavailableView {
                    Label("Console Unavailable", systemImage: "display.trianglebadge.exclamationmark")
                } description: {
                    Text(setupError)
                } actions: {
                    Button("Try Again") { Task { await connect() } }.buttonStyle(.borderedProminent)
                }
            } else if let session {
                consoleSurface(session)
            } else {
                ProgressView("Opening console…")
            }
        }
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session?.phase == .connected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        keyboardActive.toggle()
                    } label: {
                        Label("Keyboard", systemImage: keyboardActive ? "keyboard.chevron.compact.down" : "keyboard")
                    }
                }
            }
        }
        .task { await connect() }
        .onDisappear { session?.stop() }
    }

    @ViewBuilder private func consoleSurface(_ session: VNCConnection) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch session.phase {
            case .connecting:
                ProgressView("Connecting…").tint(.white)
            case .authenticating:
                ProgressView("Authenticating…").tint(.white)
            case .connected:
                framebuffer(session)
            case .failed(let message):
                ContentUnavailableView("Console Error", systemImage: "xmark.octagon",
                                       description: Text(message))
                    .foregroundStyle(.white)
            case .closed:
                ContentUnavailableView("Console Closed", systemImage: "display",
                                       description: Text("The connection ended."))
                    .foregroundStyle(.white)
            }

            // Invisible key-capture view that drives the on-screen keyboard.
            VNCKeyboard(isActive: $keyboardActive) { keysym, ctrl in
                session.tapKey(keysym, ctrl: ctrl)
            }
            .frame(width: 0, height: 0)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    @ViewBuilder private func framebuffer(_ session: VNCConnection) -> some View {
        // Fills the screen, fits the framebuffer to it by default, and supports
        // pinch-to-zoom + pan. A tap maps to a left-click at that pixel.
        VNCSurface(image: session.image, displaySize: session.displaySize) { point in
            session.sendPointer(buttonMask: 1, at: point)   // left down
            session.sendPointer(buttonMask: 0, at: point)   // left up
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func connect() async {
        setupError = nil
        session?.stop()
        session = nil
        guard let connection = app.profiles.connection(for: profile),
              let node = guest.node, let vmid = guest.vmid else {
            setupError = "Missing server connection."
            return
        }
        guard guest.type.guestKind == .qemu else {
            setupError = "Graphical console is available for virtual machines. Use the text console for containers."
            return
        }
        do {
            let ticket = try await app.api.vncProxy(connection, node: node, kind: .qemu, vmid: vmid)
            guard let port = ticket.portNumber else {
                setupError = "Proxmox returned an invalid console port."
                return
            }
            let new = VNCConnection(host: connection.host, port: port, password: ticket.ticket)
            new.start()
            session = new
        } catch {
            setupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

}

/// Hosts the framebuffer in a zoomable/pannable scroll view: it fits the image to
/// the screen by default (filling available space), supports pinch-to-zoom and
/// pan, and maps a tap to a left-click at the corresponding framebuffer pixel.
private struct VNCSurface: UIViewRepresentable {
    let image: CGImage?
    let displaySize: CGSize
    /// Called with framebuffer pixel coordinates on tap.
    let onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scroll = ZoomingScrollView()
        scroll.backgroundColor = .black
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView()
        imageView.isUserInteractionEnabled = true
        imageView.layer.magnificationFilter = .nearest   // crisp pixels when zoomed in
        scroll.addSubview(imageView)
        scroll.contentView = imageView
        context.coordinator.imageView = imageView

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        imageView.addGestureRecognizer(tap)
        return scroll
    }

    func updateUIView(_ scroll: ZoomingScrollView, context: Context) {
        context.coordinator.onTap = onTap
        guard let image, let imageView = context.coordinator.imageView else { return }
        imageView.image = UIImage(cgImage: image)
        if imageView.bounds.size != displaySize {
            imageView.frame = CGRect(origin: .zero, size: displaySize)
            scroll.contentSize = displaySize
            scroll.fitContent()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onTap: (CGPoint) -> Void
        weak var imageView: UIImageView?

        init(onTap: @escaping (CGPoint) -> Void) { self.onTap = onTap }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomingScrollView)?.centerContent()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let imageView else { return }
            // The image view's own coordinate space is 1:1 with framebuffer pixels.
            let point = gesture.location(in: imageView)
            let size = imageView.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            onTap(CGPoint(x: min(max(point.x, 0), size.width - 1),
                          y: min(max(point.y, 0), size.height - 1)))
        }
    }
}

/// A `UIScrollView` that fits its single content view to the viewport (so the
/// console fills the screen) and keeps it centred while zoomed/panned. Re-fits on
/// rotation/size changes, but never fights a zoom the user has dialled in.
private final class ZoomingScrollView: UIScrollView {
    weak var contentView: UIView?
    private var lastBounds: CGRect = .zero

    func fitContent() {
        guard let contentView, contentView.bounds.width > 0, contentView.bounds.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / contentView.bounds.width,
                      bounds.height / contentView.bounds.height)
        let wasFitted = abs(zoomScale - minimumZoomScale) < 0.001
        minimumZoomScale = fit
        maximumZoomScale = max(fit * 8, 4)
        if wasFitted || zoomScale < fit { zoomScale = fit }
        centerContent()
    }

    /// Centre the content with inset when it's smaller than the viewport.
    func centerContent() {
        guard let contentView else { return }
        let insetX = max(0, (bounds.width - contentView.frame.width) / 2)
        let insetY = max(0, (bounds.height - contentView.frame.height) / 2)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds != lastBounds {
            lastBounds = bounds
            fitContent()
        }
    }
}

/// An invisible first-responder view that captures keyboard input and forwards
/// each key as an X11 keysym. Uses `UIKeyInput` rather than a text field so the
/// Return, Tab and Backspace keys arrive as real key events (a single-line
/// `UITextField` swallows Return), and it draws nothing. An accessory bar adds the
/// keys a console needs but the iOS keyboard lacks: Esc, Tab, Ctrl, arrows, Return.
private struct VNCKeyboard: UIViewRepresentable {
    @Binding var isActive: Bool
    /// `(keysym, ctrlHeld)`.
    let onKey: (UInt32, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey) }

    func makeUIView(context: Context) -> KeyInputView {
        let view = KeyInputView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: KeyInputView, context: Context) {
        context.coordinator.onKey = onKey
        if isActive, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !isActive, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    final class Coordinator {
        var onKey: (UInt32, Bool) -> Void
        weak var view: KeyInputView?
        /// "Sticky" Ctrl: arm it, and the next key is sent as a Ctrl chord.
        var ctrlArmed = false { didSet { view?.refreshCtrl(ctrlArmed) } }

        init(onKey: @escaping (UInt32, Bool) -> Void) { self.onKey = onKey }

        func send(_ keysym: UInt32) {
            onKey(keysym, ctrlArmed)
            if ctrlArmed { ctrlArmed = false }
        }
    }

    final class KeyInputView: UIView, UIKeyInput {
        weak var coordinator: Coordinator?
        private weak var ctrlButton: UIBarButtonItem?

        override var canBecomeFirstResponder: Bool { true }

        // MARK: UIKeyInput
        var hasText: Bool { false }

        func insertText(_ text: String) {
            for scalar in text.unicodeScalars {
                switch scalar {
                case "\n", "\r": coordinator?.send(0xFF0D)   // Return
                case "\t": coordinator?.send(0xFF09)         // Tab
                default:
                    // Printable Latin-1 keysyms equal the Unicode scalar value.
                    if scalar.value >= 0x20, scalar.value <= 0xFF { coordinator?.send(scalar.value) }
                }
            }
        }

        func deleteBackward() { coordinator?.send(0xFF08) }  // Backspace

        // MARK: Accessory bar
        override var inputAccessoryView: UIView? { accessory }
        private lazy var accessory: UIToolbar = makeAccessory()

        private func makeAccessory() -> UIToolbar {
            func key(_ title: String, _ keysym: UInt32) -> UIBarButtonItem {
                UIBarButtonItem(primaryAction: UIAction(title: title) { [weak self] _ in
                    self?.coordinator?.send(keysym)
                })
            }
            let ctrl = UIBarButtonItem(title: "Ctrl", style: .plain,
                                       target: self, action: #selector(toggleCtrl))
            ctrlButton = ctrl
            let flex = { UIBarButtonItem(systemItem: .flexibleSpace) }

            let bar = UIToolbar()
            bar.items = [
                key("esc", 0xFF1B), key("tab", 0xFF09), ctrl, flex(),
                key("←", 0xFF51), key("↑", 0xFF52), key("↓", 0xFF54), key("→", 0xFF53),
                flex(), key("⏎", 0xFF0D),
            ]
            bar.sizeToFit()
            return bar
        }

        @objc private func toggleCtrl() { coordinator?.ctrlArmed.toggle() }

        func refreshCtrl(_ armed: Bool) {
            ctrlButton?.style = armed ? .done : .plain
        }
    }
}
#endif
