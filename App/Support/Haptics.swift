import SwiftUI

/// Outcome of a user-initiated action, mapped to system sensory feedback.
enum ActionFeedback: Equatable {
    /// A destructive or state-changing operation succeeded (power on/off, delete).
    case success
    /// A reversible or cautionary action completed.
    case warning
    /// An operation failed.
    case failure
    /// A discrete selection or toggle.
    case selection

    var systemFeedback: SensoryFeedback {
        switch self {
        case .success: .success
        case .warning: .warning
        case .failure: .error
        case .selection: .selection
        }
    }
}

/// Drives declarative haptics from imperative async action handlers.
///
/// `.sensoryFeedback(trigger:)` only fires when its trigger value *changes*, so a
/// bare `ActionFeedback?` would swallow two identical outcomes in a row (e.g. a
/// shutdown then a later start, both `.success`). This wraps the outcome with a
/// monotonic counter so every `signal(_:)` reliably plays, while keeping call
/// sites a one-liner. Stored as a single `@State` value; play it with
/// `.actionFeedback(feedback)`.
struct ActionFeedbackState: Equatable {
    private(set) var kind: ActionFeedback?
    private var tick = 0

    mutating func signal(_ kind: ActionFeedback) {
        self.kind = kind
        tick += 1
    }
}

extension View {
    /// Plays system sensory feedback (haptics where available) each time
    /// `state` is updated via `signal(_:)`. Safe on macOS (no-ops without an engine).
    func actionFeedback(_ state: ActionFeedbackState) -> some View {
        sensoryFeedback(trigger: state) { _, newValue in
            newValue.kind?.systemFeedback
        }
    }
}
