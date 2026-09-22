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
        // This picks up the tone too, which the chips write back.
        viewModel.reloadSettings()
    }

    // Go straight to full screen on open.
    //
    // Measured 2026-09-14: the compact drawer occupies the keyboard's slot, so
    // Messages cannot show both and expands the moment a keyboard is needed —
    // Apple documents `dismiss()` as "dismiss the extension and present the
    // keyboard", the two states are mutually exclusive by design. Since this is
    // a typing surface, arriving in the drawer only buys a glance at the
    // transcript before the first tap expands us anyway. Expanding up front
    // spends that tap better. Requested explicitly rather than left to the
    // keyboard's side effect, so there is no flash of the drawer first.
    //
    // The drawer is not lost: dragging the handle down still collapses us, and
    // `didTransition` re-lays out for it. We do not re-expand afterwards, so
    // that choice sticks for the rest of the session.
    override func didBecomeActive(with conversation: MSConversation) {
        super.didBecomeActive(with: conversation)
        if presentationStyle == .compact {
            requestPresentationStyle(.expanded)
        }
    }

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
