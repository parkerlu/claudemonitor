import SwiftUI

/// The floating composer.
///
/// Same shape as the iPhone one — what you read on top, what you type at the
/// bottom — but driven by the keyboard, because on a Mac your hands are already
/// there: ⌘↩ inserts, ⌘1–4 switch tone, Esc puts it away.
struct ComposerView: View {
    @ObservedObject var viewModel: ComposeViewModel

    var onInsert: (String) -> Void
    var onDismiss: () -> Void

    @FocusState private var chineseFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            englishCard
            if let error = viewModel.errorMessage {
                errorRow(error)
            }
            toneChips
            chineseField
            footer
        }
        .padding(14)
        .frame(minWidth: 460, minHeight: 300, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { chineseFocused = true }
        .onExitCommand { onDismiss() }
    }

    // MARK: English

    private var englishCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("英文")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if viewModel.isTranslating {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if viewModel.canInsert {
                    Text("⌘↩ 插入")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(viewModel.english.isEmpty ? " " : viewModel.english)
                .font(.title3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { insert() }

            if !viewModel.backTranslation.isEmpty {
                Divider()
                Text(viewModel.backTranslation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(viewModel.canInsert ? 0.12 : 0.05))
        )
    }

    // MARK: Tone

    private var toneChips: some View {
        HStack(spacing: 6) {
            ForEach(Array(Tone.allCases.enumerated()), id: \.element.id) { index, tone in
                Button {
                    viewModel.tone = tone
                } label: {
                    Text(tone.label)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                viewModel.tone == tone
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.secondary.opacity(0.12)
                            )
                        )
                        .foregroundStyle(viewModel.tone == tone ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Spacer()
        }
    }

    // MARK: Chinese

    private var chineseField: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.chinese.isEmpty {
                Text("用中文说")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.chinese)
                .focused($chineseFocused)
                .font(.title3)
                .frame(minHeight: 64, maxHeight: 120)
                .scrollContentBackground(.hidden)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10)))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.context.isEmpty ? viewModel.pasteContext() : viewModel.clearContext()
            } label: {
                Label(
                    viewModel.context.isEmpty ? "粘贴对方的话" : "清除上下文",
                    systemImage: viewModel.context.isEmpty ? "doc.on.clipboard" : "xmark.circle"
                )
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if !viewModel.context.isEmpty {
                Text(viewModel.context)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
            Text("Esc 收起")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Not a visible button — just somewhere to hang ⌘↩, since the
            // English card is a tap target rather than a control.
            Button("", action: insert)
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("重试") { viewModel.retry() }
                .font(.caption)
                .buttonStyle(.plain)
        }
    }

    private func insert() {
        guard viewModel.canInsert else { return }
        onInsert(viewModel.english)
    }
}
