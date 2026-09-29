import SwiftUI

/// The floating composer.
///
/// Keyboard-driven, because on a Mac your hands are already there: ⌘↩ sends,
/// ⌘1–4 switch tone, Esc puts it away. Everything reachable by key is also a
/// button, since the panel is often used with the pointer while reading a
/// conversation in another window.
struct ComposerView: View {
    @ObservedObject var viewModel: ComposeViewModel
    @ObservedObject var ui: ComposerUIState

    var onInsert: (String) -> Void
    var onDismiss: () -> Void

    @FocusState private var chineseFocused: Bool
    @State private var englishHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if ui.isSideBySide {
                HStack(alignment: .top, spacing: 12) {
                    chineseField.frame(maxWidth: .infinity, alignment: .top)
                    englishCard.frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                englishCard
                chineseField
            }

            if let error = viewModel.errorMessage {
                errorRow(error)
            }
            toneChips
            footer
        }
        .padding(14)
        .frame(minWidth: 440, maxWidth: .infinity,
               minHeight: 300, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { chineseFocused = true }
        .onExitCommand { onDismiss() }
    }

    // MARK: Header

    /// Sits to the right of the window's close button, which the panel keeps
    /// even with its title hidden.
    private var header: some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                ui.isSideBySide.toggle()
            } label: {
                Image(systemName: ui.isSideBySide
                      ? "rectangle.split.1x2" : "rectangle.split.2x1")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(ui.isSideBySide ? "改为上下排列" : "改为左右排列（窗口变宽）")

            Button {
                ui.isPinned.toggle()
            } label: {
                Image(systemName: ui.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .foregroundStyle(ui.isPinned ? Color.accentColor : .secondary)
            .help(ui.isPinned
                  ? "已钉住：点窗外不收起，发送后也留在屏幕上"
                  : "钉住：点窗外不收起，发送后也不消失")
        }
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
            }

            // 随内容长高，到上限后内部滚动。少了 fixedSize，Text 在高度不够时
            // 会截断成一行加省略号，而不是换行 —— 长句子根本读不到。
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.english.isEmpty ? " " : viewModel.english)
                        .font(.title3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { insert() }

                    if !viewModel.backTranslation.isEmpty {
                        Divider()
                        Text(viewModel.backTranslation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            }
            .frame(height: min(max(englishHeight, 30), ui.isSideBySide ? 190 : 260))
            .onPreferenceChange(ContentHeightKey.self) { englishHeight = $0 }
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
                .frame(minHeight: ui.isSideBySide ? 190 : 72,
                       maxHeight: ui.isSideBySide ? 190 : 200)
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

            // Carries ⌘↩ as well, so the shortcut and the button can never drift
            // apart. It pastes into whatever you were typing in; the actual send
            // is still your keystroke over there.
            Button("发送  ⌘↩") { insert() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canInsert)
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

/// ScrollView 会把给它的高度吃满，所以得先量出内容多高，才能让卡片
/// 短句时贴合、长句时才开始滚。
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
