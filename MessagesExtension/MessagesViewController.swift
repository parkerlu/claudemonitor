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
///    so we insert once and then collapse, leaving the send tap to the user.
final class MessagesViewController: MSMessagesAppViewController {

    private var viewModel: ComposeViewModel!
    private var hostingController: UIHostingController<ComposeView>!

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel = ComposeViewModel(settings: SettingsStore.load())

        let root = ComposeView(
            viewModel: viewModel,
            onInsert: { [weak self] text in self?.insert(text) },
            onRequestExpand: { [weak self] in
                self?.requestPresentationStyle(.expanded)
            }
        )

        hostingController = UIHostingController(rootView: root)
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

    // MARK: - Conversation lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        // Settings may have changed in the container app since we were last
        // alive; the extension process is long-lived enough for that to matter.
        viewModel.settings = SettingsStore.load()
    }

    override func didBecomeActive(with conversation: MSConversation) {
        super.didBecomeActive(with: conversation)
        // The compact drawer is only tall enough for a couple of rows, and this
        // app is a typing surface — go straight to expanded on open. We only do
        // it here, not in didTransition, so collapsing afterwards still works.
        if presentationStyle == .compact {
            requestPresentationStyle(.expanded)
        }
    }

    // MARK: - Insertion

    private func insert(_ text: String) {
        guard let conversation = activeConversation else { return }
        conversation.insertText(text) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil { return }
                self.viewModel.reset()
                self.requestPresentationStyle(.compact)
            }
        }
    }
}
