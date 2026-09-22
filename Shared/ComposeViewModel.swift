import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Drives the composer: debounce, streaming translation, back-translation,
/// and a small cache so re-picking a tone you already used is instant.
@MainActor
final class ComposeViewModel: ObservableObject {

    // MARK: Input

    @Published var chinese: String = "" {
        didSet { scheduleTranslation() }
    }

    /// Picking a tone in the composer is a lasting preference, not a per-message
    /// one — you write to the same people in the same register most days. So the
    /// chip writes straight back to the shared settings and becomes the tone the
    /// next session opens on. It is the same stored value the container app's
    /// picker edits, so the two never disagree.
    @Published var tone: Tone {
        didSet {
            guard tone != oldValue else { return }
            persistTone()
            scheduleTranslation(immediately: true)
        }
    }

    /// Optional: the message you're replying to, pasted from the clipboard.
    /// The extension can't read the conversation, so this is the one way to give
    /// the model context about what's being answered.
    @Published var context: String = "" {
        didSet { scheduleTranslation(immediately: true) }
    }

    // MARK: Output

    @Published private(set) var english: String = ""
    @Published private(set) var backTranslation: String = ""
    @Published private(set) var isTranslating: Bool = false
    @Published private(set) var errorMessage: String?

    /// Set when you tap the pencil — the English becomes directly editable and
    /// we stop overwriting it from the stream.
    @Published var isEditingEnglish: Bool = false

    var settings: AppSettings

    private var translateTask: Task<Void, Never>?
    private var backTranslateTask: Task<Void, Never>?

    /// Keyed by input + tone + context, so switching back to a tone you already
    /// tried is free and doesn't burn another request.
    private var cache: [CacheKey: String] = [:]

    private struct CacheKey: Hashable {
        let text: String
        let tone: Tone
        let context: String
    }

    init(settings: AppSettings = SettingsStore.load()) {
        self.settings = settings
        self.tone = settings.defaultTone
    }

    var canInsert: Bool {
        !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func persistTone() {
        settings.defaultTone = tone
        SettingsStore.save(settings)
    }

    /// Re-read settings the container app may have changed while we were idle,
    /// and follow the tone it holds.
    func reloadSettings() {
        settings = SettingsStore.load()
        if tone != settings.defaultTone {
            tone = settings.defaultTone
        }
    }

    // MARK: - Translation

    private func scheduleTranslation(immediately: Bool = false) {
        translateTask?.cancel()
        backTranslateTask?.cancel()
        backTranslation = ""
        errorMessage = nil

        let source = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            english = ""
            isTranslating = false
            return
        }

        // Once you've started hand-editing the English, stop clobbering it.
        guard !isEditingEnglish else { return }

        let key = CacheKey(text: source, tone: tone, context: context)
        if let cached = cache[key] {
            english = cached
            isTranslating = false
            startBackTranslation(for: cached)
            return
        }

        let delay = immediately ? 0 : settings.debounceMilliseconds

        translateTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await self.runTranslation(source: source, key: key)
        }
    }

    private func runTranslation(source: String, key: CacheKey) async {
        guard settings.isConfigured else {
            errorMessage = TranslationError.notConfigured.localizedDescription
            return
        }

        isTranslating = true
        english = ""

        let provider = OpenAICompatibleProvider(settings: settings)
        let messages = PromptBuilder.translation(
            text: source,
            tone: tone,
            glossary: settings.glossary,
            context: context.isEmpty ? nil : context
        )

        var accumulated = ""
        do {
            for try await delta in provider.stream(messages) {
                guard !Task.isCancelled else { return }
                accumulated += delta
                english = accumulated
            }
        } catch {
            guard !Task.isCancelled else { return }
            isTranslating = false
            errorMessage = (error as? TranslationError)?.localizedDescription
                ?? error.localizedDescription
            return
        }

        guard !Task.isCancelled else { return }
        isTranslating = false

        let cleaned = Self.stripWrappingQuotes(accumulated)
        english = cleaned
        cache[key] = cleaned
        startBackTranslation(for: cleaned)
    }

    private func startBackTranslation(for text: String) {
        backTranslateTask?.cancel()
        backTranslation = ""

        guard settings.showBackTranslation,
              settings.isConfigured,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        backTranslateTask = Task { [weak self] in
            guard let self else { return }
            let provider = OpenAICompatibleProvider(settings: self.settings)
            let messages = PromptBuilder.backTranslation(english: text)
            var accumulated = ""
            do {
                for try await delta in provider.stream(messages) {
                    guard !Task.isCancelled else { return }
                    accumulated += delta
                    self.backTranslation = accumulated
                }
            } catch {
                // A failed back-translation is a missing safety net, not a
                // failure of the thing you asked for. Stay quiet about it.
                self.backTranslation = ""
            }
        }
    }

    // MARK: - Actions

    func retry() {
        cache.removeAll()
        scheduleTranslation(immediately: true)
    }

    func pasteContext() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string, !text.isEmpty {
            context = text
        }
        #endif
    }

    func clearContext() {
        context = ""
    }

    func reset() {
        translateTask?.cancel()
        backTranslateTask?.cancel()
        chinese = ""
        english = ""
        backTranslation = ""
        errorMessage = nil
        isEditingEnglish = false
        isTranslating = false
    }

    func setEnglishManually(_ text: String) {
        english = text
    }

    /// The host failed to hand the text to the input field. Rare, but silence
    /// here reads as a dead tap.
    func reportInsertFailure(_ error: Error) {
        errorMessage = "没能填进输入框：\(error.localizedDescription)"
    }

    /// Models occasionally wrap the whole reply in quotes despite being told not
    /// to. Strip them rather than shipping stray punctuation into the message.
    private static func stripWrappingQuotes(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'")]
        for (open, close) in pairs {
            if trimmed.count >= 2, trimmed.first == open, trimmed.last == close {
                trimmed = String(trimmed.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return trimmed
    }
}
