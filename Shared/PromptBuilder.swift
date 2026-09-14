import Foundation

struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

/// Builds the prompts. Almost all of the perceived quality difference between
/// "a translator" and "something you'd actually send" lives in this file — far
/// more than in the choice of model.
enum PromptBuilder {

    /// Chinese (or mixed Chinese/English) in, sendable English out.
    static func translation(
        text: String,
        tone: Tone,
        glossary: [GlossaryEntry],
        context: String?
    ) -> [ChatMessage] {
        var system = """
        You are a bilingual writing assistant embedded in a messaging app. The user \
        writes in Chinese; you produce the English message they will actually send.

        You are not a literal translator. Produce English that a native speaker would \
        write in this situation — idiomatic, natural, and appropriate to the medium \
        (a chat message, not an essay).

        Hard rules:
        - Output ONLY the English message. No quotes, no preamble, no alternatives, \
        no explanation, no markdown.
        - Never add information the user did not supply, and never drop information \
        they did.
        - Keep English and technical terms the user already typed (bug, PR, deploy, \
        standup, product names) exactly as they wrote them. Do not "translate" jargon \
        into formal vocabulary.
        - Preserve the user's own line breaks.
        - If the input is already English, lightly polish it instead of rewriting it.
        - If the input is a fragment rather than a full sentence, keep it a fragment.

        \(tone.instruction)
        """

        if !glossary.isEmpty {
            let lines = glossary
                .filter { !$0.chinese.isEmpty && !$0.english.isEmpty }
                .map { "- \($0.chinese) → \($0.english)" }
                .joined(separator: "\n")
            if !lines.isEmpty {
                system += """


                Fixed terminology — always use these renderings:
                \(lines)
                """
            }
        }

        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            system += """


                For context, this is the message the user is replying to. Match its \
                register and answer what it actually asks. Do not translate it, do not \
                quote it back:
                \"\"\"
                \(context)
                \"\"\"
                """
        }

        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: text)
        ]
    }

    /// Literal back-translation, used as a safety check: it lets you confirm the
    /// English says what you meant before you send it.
    static func backTranslation(english: String) -> [ChatMessage] {
        let system = """
        Translate the English message into Chinese as literally as the Chinese language \
        allows, so the reader can verify exactly what the English says — including its \
        politeness level and any nuance that was added or lost.

        Do not improve, soften, or naturalize it. Output ONLY the Chinese. No quotes, \
        no explanation.
        """
        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: english)
        ]
    }
}
