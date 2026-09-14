import Foundation

/// Which OpenAI-compatible backend to talk to.
///
/// DeepSeek and MiniMax both expose an OpenAI-shaped `/chat/completions`
/// endpoint, so they share one provider implementation and differ only in
/// base URL and model name. `custom` lets you point at anything else without
/// touching code.
enum ProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case deepseek
    case minimax
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .minimax: return "MiniMax"
        case .custom: return "自定义"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1"
        case .minimax: return "https://api.minimax.chat/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .minimax: return "MiniMax-Text-01"
        case .custom: return ""
        }
    }
}

/// Settings shared between the container app (where you edit them) and the
/// Messages extension (where they are read). They live in the App Group so
/// both processes see the same values.
///
/// The API key is stored in the App Group's `UserDefaults` rather than the
/// Keychain. That is a deliberate trade for a personal, non-distributed build:
/// the key never leaves your own device, and App Group defaults are already
/// sandboxed to this app. If you ever distribute this, move it to the Keychain.
struct AppSettings: Codable, Sendable, Equatable {
    var provider: ProviderKind = .deepseek
    var baseURL: String = ProviderKind.deepseek.defaultBaseURL
    var model: String = ProviderKind.deepseek.defaultModel
    var apiKey: String = ""

    var defaultTone: Tone = .neutral

    /// Show a literal Chinese back-translation under the English so you can
    /// confirm the meaning did not drift before sending.
    var showBackTranslation: Bool = true

    /// How long to wait after the last keystroke before translating.
    var debounceMilliseconds: Int = 350

    /// Fixed translations for names, products, and jargon. Injected into the
    /// prompt verbatim.
    var glossary: [GlossaryEntry] = []

    var isConfigured: Bool {
        !apiKey.isEmpty && !baseURL.isEmpty && !model.isEmpty
    }

    /// Keep base URL and model in sync when the provider changes, but leave
    /// them alone if you have hand-edited them.
    mutating func applyProviderDefaults() {
        baseURL = provider.defaultBaseURL
        model = provider.defaultModel
    }
}

struct GlossaryEntry: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var chinese: String
    var english: String
}

/// Read/write access to the shared settings blob.
enum SettingsStore {
    /// Must match the App Group configured on both targets in `project.yml`.
    static let appGroupID = "group.com.example.endraft"

    private static let key = "app_settings_v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
