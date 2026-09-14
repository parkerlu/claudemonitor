import Foundation

/// The register the generated English should be written in.
///
/// This is the single biggest lever on whether a translation feels "sendable",
/// so it is surfaced directly in the composer as a chip row rather than buried
/// in settings.
enum Tone: String, CaseIterable, Codable, Identifiable, Sendable {
    case casual
    case neutral
    case formal
    case concise

    var id: String { rawValue }

    /// Label shown on the chip in the composer.
    var label: String {
        switch self {
        case .casual: return "随意"
        case .neutral: return "中性"
        case .formal: return "正式"
        case .concise: return "简短"
        }
    }

    /// Appended to the system prompt.
    var instruction: String {
        switch self {
        case .casual:
            return "Tone: casual and friendly, the way you'd text a colleague you know well. Contractions are fine. Avoid stiff or corporate phrasing."
        case .neutral:
            return "Tone: neutral and clear — polite but not formal. This is the default register for everyday chat."
        case .formal:
            return "Tone: professional and courteous, suitable for a client, a manager, or a first contact. Avoid slang, but do not be stiff or archaic."
        case .concise:
            return "Tone: as short as possible while staying polite and unambiguous. Strip filler words. Prefer one sentence."
        }
    }
}
