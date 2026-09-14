import Messages
import SwiftUI
import UIKit

/// Host for the composer inside Messages.
///
/// Two constraints from the Messages extension API shape everything here:
///
/// 1. There is no way to read what the user has already typed in the Messages
///    input field, so all typing has to happen inside this view controller.
/// 2. `insertText` *appends* to the input field and there is no API to clear it,
///    so we insert once and then dismiss, leaving the send tap to the user.
final class MessagesViewController: MSMessagesAppViewController {

    private var viewModel: ComposeViewModel!
    private var hostingController: UIHostingController<ComposeView>!

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel = ComposeViewModel(settings: SettingsStore.load())

        hostingController = UIHostingController(
            rootView: makeRoot(isCompact: presentationStyle == .compact)
        )
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func makeRoot(isCompact: Bool) -> ComposeView {
        ComposeView(
            viewModel: viewModel,
            isCompact: isCompact,
            onInsert: { [weak self] text in self?.insert(text) }
        )
    }

    // MARK: - Conversation lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        // Settings may have changed in the container app since we were last
        // alive; the extension process is long-lived enough for that to matter.
        viewModel.settings = SettingsStore.load()
    }

    // Open in the compact drawer so the conversation stays visible, and never
    // expand on our own.
    //
    // Measured 2026-09-14: focusing the text field is enough to expand us. The
    // drawer occupies the keyboard's slot, so Messages cannot show both and
    // switches to full screen the moment a keyboard is needed. Apple's own
    // `dismiss()` is documented as "dismiss the extension and present the
    // keyboard" — the two states are mutually exclusive by design. So typing
    // and seeing the transcript cannot be had at once; do not try again.
    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        hostingController.rootView = makeRoot(isCompact: presentationStyle == .compact)
    }

    // MARK: - Insertion

    private func insert(_ text: String) {
        guard let conversation = activeConversation else { return }
        conversation.insertText(text) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    // Otherwise the tap looks like it did nothing at all.
                    self.viewModel.reportInsertFailure(error)
                    return
                }
                self.viewModel.reset()
                // Not requestPresentationStyle(.compact) — we already open in the
                // drawer, so that would be a no-op. `dismiss()` closes the
                // extension outright and raises the keyboard, which puts the
                // filled-in field and the send button straight under your thumb.
                self.dismiss()
            }
        }
    }
}
