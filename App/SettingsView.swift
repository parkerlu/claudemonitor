import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsStore.load()
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .onChange(of: settings.provider) { _, _ in
                    settings.applyProviderDefaults()
                }

                LabeledContent("Base URL") {
                    TextField("https://…", text: $settings.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Model") {
                    TextField("模型名", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }

                SecureField("API Key", text: $settings.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("翻译服务")
            } footer: {
                Text("Key 只保存在本机的 App Group 里，不会离开这台设备。")
            }

            Section("测试") {
                Button {
                    runTest()
                } label: {
                    HStack {
                        Text("试翻一句")
                        if isTesting {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(!settings.isConfigured || isTesting)

                if let testResult {
                    Text(testResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("默认语气", selection: $settings.defaultTone) {
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
            } header: {
                Text("默认行为")
            } footer: {
                Text("回译会把英文再直译回中文，用来确认意思没跑偏。它会多花一次请求。")
            }

            Section {
                NavigationLink {
                    GlossaryView(glossary: $settings.glossary)
                } label: {
                    LabeledContent("术语表", value: "\(settings.glossary.count) 条")
                }
            } footer: {
                Text("公司名、产品名、人名、行业黑话的固定译法。会原样注入到 prompt 里。")
            }
        }
        .navigationTitle("设置")
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
