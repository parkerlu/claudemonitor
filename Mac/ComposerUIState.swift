import SwiftUI

/// Panel-shape state: not settings, just how the window happens to be arranged
/// right now.
@MainActor
final class ComposerUIState: ObservableObject {

    /// Pinned: clicking away does not put the panel back, and inserting leaves
    /// it open so you can write the next line straight after.
    @Published var isPinned = false

    /// Chinese and English side by side in a wider window, rather than stacked.
    ///
    /// Deliberately not persisted — this is a per-moment choice, like resizing a
    /// window, not a preference worth remembering. Tone is the opposite and is
    /// stored; see `ComposeViewModel.tone`.
    @Published var isSideBySide = false

    var windowSize: NSSize {
        isSideBySide ? NSSize(width: 880, height: 380)
                     : NSSize(width: 480, height: 420)
    }
}
