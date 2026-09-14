# EnDraft

一个只给自己用的 iMessage 插件：在插件里用中文（打字或语音）说，实时得到可以直接发出去的英文，点一下就填进 iMessage 输入框。

不上架、不过审、key 只存在本机。

> 📄 **动手前先读** [`docs/SPEC.md`](docs/SPEC.md)（架构与设计决策）和
> [`docs/TASKS.md`](docs/TASKS.md)（按顺序的实施计划）。
>
> ⚠️ 当前代码是在没有 Xcode 的环境里写的，**从未编译过**，预期需要修几个小错误。

## 它为什么是插件而不是键盘

自定义键盘要自研拼音引擎（词库 + 切分 + n-gram 排序），是这个想法里最贵的一块。
而在 iMessage 插件里，输入框是**你自己的**，系统中文键盘直接可用 —— 拼音、九宫格、手写、
**以及键盘上的语音听写**，全部零代码拿到。

代价是三条 Messages 扩展的硬限制，代码里都已经绕开了：

| 限制 | 应对 |
|---|---|
| 读不到 iMessage 输入框里已有的文字 | 打字发生在插件内部 |
| 读不到聊天记录 | 「粘贴对方的话」按钮做剪贴板桥接 |
| 不能替你发送 | 插入后收起，最后那下发送你自己点 |

## 交互

```
点 "+" → EnDraft → 自动展开
  ↓
打中文（或按键盘麦克风说中文）
  ↓
停手 350ms → 英文流式出现
             ├── 语气 chips：随意 / 中性 / 正式 / 简短
             ├── 回译校验：把英文直译回中文，确认意思没跑偏
             └── ✏️ 可直接手改
  ↓
点一下英文卡片 → 填进 iMessage 输入框 → 你点发送
```

## 构建

需要 macOS + Xcode 15+。仓库里不含 `.xcodeproj`，用 XcodeGen 生成：

```bash
brew install xcodegen
xcodegen generate
open EnDraft.xcodeproj
```

### 构建前必须改的三处

1. **`project.yml` → `DEVELOPMENT_TEAM`**：填你的 10 位 Team ID（Xcode → Settings → Accounts 里能看到）。
2. **Bundle ID**：把 `com.example.endraft` 和 `com.example.endraft.messages` 换成你自己的反向域名。
3. **App Group**：把 `group.com.example.endraft` 换成你自己的，并在 Apple Developer 后台
   （或让 Xcode 的 Automatic Signing 自动创建）注册它。**主 App 和扩展必须用同一个 group**，
   否则扩展读不到你填的 API key。

改完重新 `xcodegen generate`。

### 图标

Messages 扩展需要一套 `iMessage App Icon` 资源，否则在 Messages 的 "+" 菜单里是一块空白。
在 Xcode 里给 `EnDraftMessages` target 新建一个 iMessage App Icon asset 即可，随便放张图。

### 签名有效期

- 免费 Apple ID：**7 天**后失效，得重新连 Mac 装一次。
- $99 开发者账号：1 年。日常用的话建议买，不然会被这个折磨到放弃。

## 配置

装好后打开主 App `EnDraft`：

1. 选服务商（DeepSeek / MiniMax / 自定义），Base URL 和 Model 会自动填默认值
2. 粘贴 API key
3. 点「试翻一句」确认通了 —— 如果报错，错误信息里会带接口返回的原文
4. 可选：调默认语气、回译开关、防抖时长、术语表

> MiniMax 的默认 endpoint 和模型名可能需要按你账号的实际情况改，
> Base URL 和 Model 都是可编辑的。

## 结构

```
Shared/                      # 主 App 和扩展共用，与 UI 无关
  Tone.swift                 # 四种语气及其 prompt 指令
  AppSettings.swift          # App Group 里的共享设置
  PromptBuilder.swift        # ★ 质量主要由这里决定，不是由模型决定
  TranslationProvider.swift  # 协议
  OpenAICompatibleProvider.swift  # DeepSeek / MiniMax / 任意 OpenAI 兼容接口
  ComposeViewModel.swift     # 防抖、流式、缓存、回译

MessagesExtension/
  MessagesViewController.swift    # MSMessagesAppViewController
  ComposeView.swift               # composer UI

App/
  SettingsView.swift
  GlossaryView.swift
```

引擎和 UI 是分开的：`Shared/` 里没有任何 Messages 相关的东西。
以后想做成键盘扩展、Mac App 或独立 App，换的只是外壳。

## 想调质量先改哪里

`Shared/PromptBuilder.swift`。语气指令、"保留技术词不翻"、术语表注入、回译的严格度
都在那一个文件里，改完立刻见效 —— 比换模型的收益大得多。

## 路线

详见 [`docs/TASKS.md`](docs/TASKS.md)。摘要：

| | 内容 |
|---|---|
| **M0–M1** | 编译通过、装到真机、云端翻译跑通（代码已写，待验证） |
| **M2** | 真机 spike：端侧 framework 和录音在 App Extension 里到底能不能用 |
| **M3** | 三层引擎阶梯 —— 端侧草稿（0 延迟）+ 端侧润色（离线可用）+ 云端润色 |
| **M4** | 语音输入（端侧识别，**不走云端 ASR**） |
| **M5** | 多候选横滑、常用句收藏、中式表达高亮 |

两个反直觉但重要的结论，展开在 SPEC 里：

- **语音不要用 DeepSeek/MiniMax 做。** DeepSeek 根本没有 ASR 接口；
  而且云端 ASR 在延迟、成本、离线、隐私上全面输给 iOS 端侧识别。
- **先把 `PromptBuilder.swift` 调到满意，再去接端侧模型。**
  译文质量的差距主要在 prompt 里，不在模型里。
