import SwiftUI

/// The Mac keeps its own copy of the settings — it cannot share an App Group
/// with the iPhone, so the key is entered once here too.
struct MacSettingsView: View {
    @State private var settings = SettingsStore.load()
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("翻译服务") {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .onChange(of: settings.provider) { _, _ in
                    settings.applyProviderDefaults()
                }
                TextField("Base URL", text: $settings.baseURL)
                TextField("Model", text: $settings.model)
                SecureField("API Key", text: $settings.apiKey)
                Text("Key 只保存在这台 Mac 上。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("测试") {
                HStack {
                    Button("试翻一句") { runTest() }
                        .disabled(!settings.isConfigured || isTesting)
                    if isTesting { ProgressView().controlSize(.small) }
                }
                if let testResult {
                    Text(testResult)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("行为") {
                Picker("语气", selection: $settings.defaultTone) {
                    ForEach(Tone.allCases) { tone in
                        Text(tone.label).tag(tone)
                    }
                }
                Toggle("显示回译校验", isOn: $settings.showBackTranslation)
                Stepper(
                    "停顿 \(settings.debounceMilliseconds) ms 后翻译",
                    value: $settings.debounceMilliseconds,
                    in: 150...1500,
                    step: 50
                )
                Text("语气记的是你在浮窗里最后选的那个，两边是同一个值。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("快捷键") {
                LabeledContent("唤出浮窗", value: "⌥Space")
                Text("浮窗里：⌘1–4 切语气，⌘↩ 插入，Esc 收起。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onChange(of: settings) { _, newValue in
            SettingsStore.save(newValue)
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        let current = settings
        Task {
            let provider = OpenAICompatibleProvider(settings: current)
            let messages = PromptBuilder.translation(
                text: "这个 bug 我已经 fix 了，等会儿 push 上去，麻烦你再 review 一下。",
                tone: current.defaultTone,
                glossary: current.glossary,
                context: nil
            )
            do {
                let result = try await provider.complete(messages)
                await MainActor.run {
                    testResult = result
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = (error as? TranslationError)?.localizedDescription
                        ?? error.localizedDescription
                    isTesting = false
                }
            }
        }
    }
}
