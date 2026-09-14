import SwiftUI

/// The composer shown inside the Messages app drawer.
///
/// Layout mirrors Messages itself: the result you read sits up in the content
/// area, the field you type into is pinned to the bottom just above the
/// keyboard. Tone chips sit directly over the input because that is where your
/// thumb already is, and they change the card above them.
struct ComposeView: View {
    @ObservedObject var viewModel: ComposeViewModel

    /// True while we're in the bottom drawer rather than full screen. The
    /// drawer is short, so anything non-essential is dropped there.
    var isCompact: Bool

    /// Called when you tap the English card. Hands the text to the Messages
    /// input field.
    var onInsert: (String) -> Void

    @FocusState private var chineseFocused: Bool

    var body: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            if !isCompact {
                contextRow
            }
            englishCard

            // 恒在。抽屉里它塌成 0；被撑到全屏时它把输入区顶到键盘上方 ——
            // 少了它，内容会在多出来的高度里居中，上下各留一大片空白。
            Spacer(minLength: 0)

            if let error = viewModel.errorMessage {
                errorRow(error)
            }
            toneChips
            chineseField
        }
        .padding(.horizontal, 16)
        .padding(.top, isCompact ? 8 : 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Messages composites us over the conversation, and the extension view
        // is transparent by default — against a photo background the chips and
        // placeholder wash out completely. This is a text tool, so legibility
        // beats the floating look.
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        // 无条件聚焦。别加 `if !isCompact` —— onAppear 跑在 didBecomeActive 之前，
        // 那时 presentationStyle 还是 compact，判断永远为假，焦点永远拿不到，
        // 于是键盘不弹、扩展也就撑不开。而撑开它的恰恰是键盘本身：
        // didBecomeActive 里的 requestPresentationStyle(.expanded) 会被 Messages 忽略。
        // onAppear 只触发一次，所以用户之后把抽屉拖回去，我们不会再抢焦点。
        .onAppear { chineseFocused = true }
    }

    // MARK: Tone

    private var toneChips: some View {
        HStack(spacing: 8) {
            ForEach(Tone.allCases) { tone in
                Button {
                    viewModel.tone = tone
                } label: {
                    Text(tone.label)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                viewModel.tone == tone
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.secondary.opacity(0.12)
                            )
                        )
                        .foregroundStyle(viewModel.tone == tone ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Context (clipboard bridge)

    private var contextRow: some View {
        Group {
            if viewModel.context.isEmpty {
                HStack {
                    Button {
                        viewModel.pasteContext()
                    } label: {
                        Label("粘贴对方的话作为上下文", systemImage: "doc.on.clipboard")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.context)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        viewModel.clearContext()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            }
        }
    }

    // MARK: Chinese input

    private var chineseField: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.chinese.isEmpty {
                Text("用中文说，或按键盘上的麦克风直接讲")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.chinese)
                .focused($chineseFocused)
                .frame(minHeight: isCompact ? 40 : 72,
                       maxHeight: isCompact ? 72 : 120)
                .scrollContentBackground(.hidden)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.10)))
    }

    // MARK: English output

    private var englishCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("英文")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if viewModel.isTranslating {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                if viewModel.canInsert {
                    Button {
                        viewModel.isEditingEnglish.toggle()
                    } label: {
                        Image(systemName: viewModel.isEditingEnglish
                              ? "checkmark.circle" : "pencil")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.isEditingEnglish {
                TextEditor(text: Binding(
                    get: { viewModel.english },
                    set: { viewModel.setEnglishManually($0) }
                ))
                .frame(minHeight: isCompact ? 44 : 64,
                       maxHeight: isCompact ? 80 : 140)
                .scrollContentBackground(.hidden)
            } else {
                Text(viewModel.english.isEmpty ? " " : viewModel.english)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard viewModel.canInsert else { return }
                        onInsert(viewModel.english)
                    }
            }

            if !viewModel.backTranslation.isEmpty {
                Divider()
                Text(viewModel.backTranslation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.canInsert && !viewModel.isEditingEnglish && !isCompact {
                Text("点一下即可填入聊天输入框")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(isCompact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(viewModel.canInsert ? 0.10 : 0.04))
        )
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("重试") { viewModel.retry() }
                .font(.footnote)
                .buttonStyle(.plain)
        }
    }
}
