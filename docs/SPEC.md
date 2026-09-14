# EnDraft 技术规格

> 面向实现者（包括 Mac 上的 Claude Code）。读完这份就应该知道要建什么、为什么这么建、
> 以及哪几件事必须先在真机上验证再动手。

---

## 1. 一句话

在 iMessage 插件里用中文说话或打字，实时得到**可以直接发出去的**英文，点一下填进聊天输入框。

注意措辞：不是"翻译成英文"，是"可以直接发出去的英文"。这两者的差别决定了下面所有设计。
系统自带的翻译已经能做前者了；这个项目存在的理由是后者 —— 语气对不对、得不得体、
术语有没有翻错、我敢不敢按发送。

**自用项目。不上架、不过审、不做多用户、key 不离开本机。** 凡是为分发才需要的东西
（代理后端、Keychain、隐私政策、账号体系）一律不做。

---

## 2. 为什么是 iMessage 插件

自定义键盘需要自研拼音引擎（词库 + 拼音切分 + n-gram 候选排序），是整个想法里最贵的一块，
轻松吃掉两个月。

而 iMessage 插件里的输入框**是我们自己的**，所以系统中文键盘直接可用：拼音、九宫格、双拼、
手写、Emoji、粘贴，**以及键盘上的语音听写** —— 全部零代码拿到。

代价是 Messages 扩展的三条硬限制。它们不可绕过，只能设计成不需要它们：

| 限制 | 应对 |
|---|---|
| 读不到 iMessage 输入框里已有的文字（无此 API） | 打字发生在插件内部 |
| 读不到聊天记录（只能拿到对方的匿名 UUID） | 「粘贴对方的话」按钮做剪贴板桥接 |
| 不能替用户发送 | 插入后收起，最后那下发送由用户点 |
| `insertText` 是**追加**，且没有清空输入框的 API | 插入后立刻 `reset()`，避免二次插入拼接出 `中文English` |

> 推论：**永远是「打字 + 2 次点击」，不可能做到真正的"一键"。** 这是 API 限制，不是实现问题。

---

## 3. 架构

```
┌─────────────────────────────────────────────┐
│  MessagesExtension/   (壳，可替换)            │
│    MessagesViewController  ← MSMessagesApp… │
│    ComposeView             ← SwiftUI        │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│  Shared/   (引擎，不依赖 Messages)            │
│                                              │
│   ComposeViewModel     防抖 / 流式 / 缓存     │
│   PromptBuilder        ★ 质量主要在这里        │
│   TranslationProvider  协议                   │
│     ├─ AppleTranslationProvider   端侧，免费   │
│     ├─ FoundationModelsProvider   端侧，免费   │
│     └─ OpenAICompatibleProvider   云端         │
│   SpeechTranscriber    端侧语音识别            │
│   AppSettings          App Group 共享设置      │
└──────────────────────────────────────────────┘
```

**铁律：`Shared/` 里不允许出现 `import Messages`。**

理由是这个项目大概率会长出第二个壳（自定义键盘、Mac App、独立 App）。只要这条守住，
换壳就是纯增量；一旦破了，就得重写引擎。

---

## 4. 翻译引擎阶梯

核心思路：**用免费的端侧模型消灭感知延迟，用云端模型保证质量。**

用户停手的那一刻立刻看到一版英文（端侧，0 延迟，灰色显示），云端结果 300~800ms 后
静默替换上来（变成正常颜色）。用户的等待感基本归零。

### Tier 0 — Apple Translation framework（即时草稿）

- `import Translation`，iOS 17.4 起有系统 UI，**iOS 18 起有可编程的 `TranslationSession`**
- 端侧、免费、离线、无 key、几十毫秒
- **只翻译，不润色**：给不了语气控制、认不了术语表、不认上下文
- 首次使用需要下载语言包，会弹系统提示
- 是 SwiftUI 绑定的（靠 `.translationTask` 修饰符 vend 出 session），不是随处可调的裸 API

**定位：草稿层 + 彻底离线时的兜底。不能作为唯一引擎。**

### Tier 1 — Foundation Models framework（端侧润色）

- `import FoundationModels`，iOS 26 起，Apple Intelligence 端侧约 3B 模型
- 免费、离线、隐私最好，而且**会润色**，能理解语气指令
- 限制：
  - 只在支持 Apple Intelligence 的机型上可用（先查 `SystemLanguageModel.default.availability`）
  - 上下文窗口不大（几千 token 量级），够用但不能塞长文
  - 有内容安全护栏，偶尔会拒答，必须有降级路径
  - 质量明显不如云端大模型，长句和微妙语气上差距会显出来

**定位：离线模式的主力；在线时作为云端到达前的更好草稿。**

### Tier 2 — DeepSeek / MiniMax（云端润色）

- 已实现：`OpenAICompatibleProvider`，两家都是 OpenAI 兼容接口，只差 base URL 和模型名
- 质量最好，术语表、上下文、语气都吃得住
- 300~1500ms，要花钱，要联网

**定位：默认的最终结果。**

### 降级顺序

```
在线 + 配了 key   →  Tier 0 出草稿  →  Tier 2 替换
在线 + 没配 key   →  Tier 1（若可用） → 否则 Tier 0
离线             →  Tier 1（若可用） → 否则 Tier 0
Tier 0 也不可用   →  明确报错，不要假装在工作
```

设置页给一个开关：**「省流/隐私模式」** —— 打开后只用端侧，永不联网。

### UI 呈现

- 草稿态：英文文字用 `.secondary` 颜色 + 右上角一个小的「草稿」标签
- 替换：淡入过渡，不要跳变
- 已经是最终态就不要再显示任何 loading

---

## 5. 语音输入

### ❌ 不要用云端 ASR

- **DeepSeek 没有语音识别接口**，它是纯文本 API
- MiniMax 是否有公开 ASR 端点不确定（TTS 是有的）
- 即便有，在这个场景里也是全面劣势：多一次往返（+300~800ms）、多一份钱、
  离线不可用、录音上云隐私更差

### ✅ 方案 A：系统键盘听写（默认，零代码）

用户在我们的中文输入框里，按系统键盘上的麦克风键说话。**已经可以用了，不需要写任何代码。**
端侧识别、免费、离线、中文质量很好。

先用这个。很可能它就够了。

### ✅ 方案 B：自己的「按住说话」按钮（体验升级）

如果觉得每次要先调出键盘再点麦克风太绕，做一个大的按住说话按钮：

- iOS 17–25：`SFSpeechRecognizer(locale: zh-CN)`，**设 `requiresOnDeviceRecognition = true`**
  （先查 `supportsOnDeviceRecognition`），配 `AVAudioEngine` 取麦克风流
- iOS 26+：新的 `SpeechAnalyzer` / `SpeechTranscriber` API，更适合流式长句
- 需要在**扩展的 Info.plist** 里加 `NSMicrophoneUsageDescription` 和
  `NSSpeechRecognitionUsageDescription`（加在主 App 的没用）
- 边说边把识别结果写进 `chinese`，防抖逻辑会自动触发翻译 —— 说完就已经有英文了

> ⚠️ 待验证：App Extension 里录音 + 语音识别是否受限。见 §7。

### 交互建议

按住说话 → 松手 → 中文落进输入框（**可编辑**，识别错了能改）→ 自动翻译。
不要做成「松手直接出英文」，中间那一步必须能看见能改，否则识别错了你根本不知道发了什么出去。

---

## 6. Provider 契约

新引擎只要实现这个协议就能接进来，`ComposeViewModel` 不用改：

```swift
protocol TranslationProvider: Sendable {
    func stream(_ messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}
```

端侧引擎接入时的注意点：

- **Apple Translation 不是 chat 接口**，没有 system prompt 概念。实现时从 `messages`
  里取最后一条 user content 当作待翻译文本，忽略 system。语气指令对它无效，这是预期行为。
- **Foundation Models 是 chat-like 的**，`LanguageModelSession(instructions:)` 对应 system，
  `streamResponse(to:)` 对应 stream。注意它的流式语义可能是**累积快照**而非增量 delta，
  接入时要确认，否则文字会重复拼接。
- 两者都不会抛网络错误，但会抛"模型不可用/语言包未下载/被护栏拒绝"，
  需要在 `TranslationError` 里加对应 case。

新增一个 `EngineRouter`，负责按 §4 的降级顺序挑 provider，并同时驱动草稿层和最终层。
`ComposeViewModel` 只跟 router 打交道。

---

## 7. 动手前必须验证的 spike

**这几件事会改变架构，先花半天验证，不要先写代码。** 每条都只需要一个最小 demo。

| # | 要验证什么 | 怎么验 | 如果不行 |
|---|---|---|---|
| 1 | `Translation` framework 在 **App Extension** 里能否使用 | 扩展里跑一次 `TranslationSession` 翻一句 | Tier 0 取消，草稿层改用 Tier 1 |
| 2 | `FoundationModels` 在 **App Extension** 里能否使用，以及会不会被内存限制杀掉 | 扩展里跑一次 `LanguageModelSession` 流式输出 | Tier 1 取消，离线模式退化成 Tier 0 直译 |
| 3 | 扩展里能否**录音 + 语音识别** | 扩展里跑 `AVAudioEngine` + `SFSpeechRecognizer` | 方案 B 取消，只保留系统键盘听写（方案 A 反正不受影响） |
| 4 | iMessage 扩展的实际**内存上限** | 逐步加载，看什么时候被 jettison | 决定端侧模型能不能留在扩展里 |
| 5 | MiniMax 的实际 endpoint / 模型名 | 拿真 key curl 一次 | 改 `AppSettings` 里的默认值 |

第 1、2 条我无法从文档确认，Apple 没有明确说明 App Extension 的支持情况。**必须实测。**

---

## 8. 延迟与成本预算

目标（P50）：

| 阶段 | 目标 |
|---|---|
| 停手 → 草稿出现 | < 100ms |
| 停手 → 云端最终版完成 | < 900ms |
| 点击译文 → 填进输入框 | 瞬间（无网络） |

成本量级：一句话约 100 input + 60 output token。按重度使用 200 句/天算，
一个月大概几毛到一块钱人民币。**不需要为成本做任何优化**，缓存做了是为了体验不是为了省钱。

---

## 9. 该盯的指标

自用项目也值得埋这几个，因为它们直接告诉你该改哪里：

- **上屏率** —— 译文出来了，实际点发的比例。低于 40% 说明译文不可信，
  问题在 `PromptBuilder` 不在模型
- **编辑率** —— 上屏前手改的比例
- **停手 → 译文就绪** 的 P50 / P90
- **草稿被云端替换后，两版差异大不大** —— 如果经常一样，说明可以省掉云端那层

---

## 10. 已知限制（不要试图解决）

- 只在 Messages 里能用。想要全局就得做键盘扩展，那才需要拼音引擎
- 读不到对方的消息，只能靠粘贴
- 不能代发，永远是两次点击
- 免费 Apple ID 签名 7 天失效；$99 开发者账号 1 年
- iOS 17 之后 iMessage App 被收进「+」菜单，发现性变差（自用无所谓）

---

## 11. 想调质量先改哪里

`Shared/PromptBuilder.swift`。**语气指令、"保留技术词不翻"、术语表注入、回译严格度
全在那一个文件里，改完立刻见效 —— 收益远大于换模型。**

在花时间接端侧模型之前，先把这个文件调到满意。
