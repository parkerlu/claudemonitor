# EnDraft 实施计划

> 按顺序做。每个里程碑都有明确的「做完的标准」—— 没达到就别进下一个。
> 详细背景见 [SPEC.md](./SPEC.md)。

当前状态：**M1 的代码已写好但从未编译过**（是在 Linux 容器里写的，没有 Xcode）。
所以 M0 的第一件事是让它编译通过。

---

## M0 — 先跑起来

目标：手机上能打开插件，看见界面。还不用能翻译。

- [ ] `brew install xcodegen && xcodegen generate && open EnDraft.xcodeproj`
- [ ] 改 `project.yml` 三处：`DEVELOPMENT_TEAM`（10 位 Team ID）、两个 Bundle ID、App Group
- [ ] **确认主 App 和扩展用的是同一个 App Group** —— 不一致的话扩展读不到 key，
      而且不会报错，只会表现为"一直提示没配置"，很难查
- [ ] 修编译错误（预期会有几个，代码没编译过）
- [ ] 给 `EnDraftMessages` target 加一套 iMessage App Icon，否则「+」菜单里是空白
- [ ] 装到真机，在 Messages 里打开插件

**做完的标准：** Messages 里点「+」→ EnDraft → 展开 → 看到输入框和语气 chips。

---

## M1 — 云端翻译跑通

目标：现有功能真的能用。

- [ ] 主 App 里填 DeepSeek key，点「试翻一句」通过
- [ ] 插件里打中文 → 英文流式出现
- [ ] 点译文 → 填进 Messages 输入框
- [ ] 切语气 → 结果变化；切回来 → 走缓存，瞬间
- [ ] 回译校验显示正常
- [ ] 断网 → 出的是清楚的错误，不是无限转圈
- [ ] 填 MiniMax key，确认 Base URL / Model 对不对（见 SPEC §7 第 5 条）

**做完的标准：** 你真的用它发出去了 10 条消息。

> 到这里先停下来实际用几天。后面的东西都是在优化一个你还没验证过值不值得用的东西。

---

## M2 — 验证 spike（半天，先做完再写 M3/M4 的代码）

见 [SPEC.md §7](./SPEC.md#7-动手前必须验证的-spike)。

- [x] `Translation` framework —— 框架支持，但中文语言包未下载（`.supported`）
- [x] `FoundationModels` —— **不可用**，`.unavailable(.deviceNotEligible)`，区域限制，修不了
- [ ] 扩展里能否录音 + 语音识别 —— 未验证（还没轮到语音）
- [x] 扩展的实际内存上限 —— 容器 App 空载 10.2 MB / 跑完探针 22.8 MB

**已完成（2026-09-14）。** 详见 [SPEC.md §7 实测结论](./SPEC.md#7-动手前必须验证的-spike)。

---

## M3 — 离线与草稿层 ❌ 已放弃

> **2026-09-14 决定不做。** M2 实测后 Tier 1 机型不合格，Tier 0 只能直译 ——
> 给不了语气控制、术语表和上下文，而"得体"正是这个项目存在的理由。
> 为一个只能直译的离线层搭整套 router，收益不足。Parker 拍板：只用 DeepSeek。
>
> 换设备（非中国大陆区域、支持 Apple Intelligence）后可以重开这一节。
> 下面的清单原样保留。

目标：停手瞬间就有英文；没网也能用。

- [ ] `TranslationError` 加端侧相关的 case（模型不可用 / 语言包未下载 / 被护栏拒绝）
- [ ] `AppleTranslationProvider`（若 spike 1 通过）
      - 注意：不是 chat 接口，取 messages 最后一条 user content，忽略 system
- [ ] `FoundationModelsProvider`（若 spike 2 通过）
      - 注意：确认流式是**增量 delta 还是累积快照**，搞错会重复拼接
      - 先查 `SystemLanguageModel.default.availability`
- [ ] `EngineRouter`：按 SPEC §4 的降级顺序选 provider，同时驱动草稿层和最终层
- [ ] `ComposeViewModel` 改成只跟 router 打交道
- [ ] 草稿态 UI：`.secondary` 颜色 + 「草稿」小标签；云端到达后淡入替换
- [ ] 设置页加「省流/隐私模式」开关（只用端侧，永不联网）
- [ ] 飞行模式下测一遍

**做完的标准：** 飞行模式下打中文，仍然出英文；联网时停手 100ms 内就看得到草稿。

---

## M4 — 语音

- [ ] 先确认系统键盘的麦克风听写在插件输入框里好不好用 —— **很可能到这里就够了，够了就跳过下面**
- [ ] （可选）自己的「按住说话」按钮：
      - iOS 17–25 用 `SFSpeechRecognizer(locale: zh-CN)` + `requiresOnDeviceRecognition = true`
      - iOS 26+ 可用 `SpeechAnalyzer` / `SpeechTranscriber`
      - **在扩展的 Info.plist** 加 `NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`
- [ ] 识别结果写进 `chinese`，中间那步**必须可见可编辑** —— 不要做成松手直接出英文
- [ ] 松手后自动触发翻译

**做完的标准：** 按住说一句中文，松手，2 秒内看到可发送的英文。

> ⚠️ 不要用 DeepSeek/MiniMax 做语音识别。DeepSeek 没有 ASR 接口；
> 云端 ASR 在延迟、成本、离线、隐私上全面输给端侧。见 SPEC §5。

---

## M5 — 体验增强（按你实际用下来的痛点挑，不必全做）

- [ ] **多候选横滑** —— 一次给 2–3 个不同语气的版本并排，比切 chips 再等一次快
- [ ] **常用句收藏 / 历史复用** —— 重复话术多的场景收益最大
- [ ] **中式表达高亮** —— 标出可能显得生硬或无礼的措辞并给替代
- [ ] 快捷短语（"稍后回复你"之类）一键上屏
- [ ] 埋 SPEC §9 的四个指标

---

## 不要做的事

- ❌ 代理后端 / Keychain / 账号体系 —— 自用项目，key 不离开本机
- ❌ 云端语音识别 —— 见 SPEC §5
- ❌ 在 `Shared/` 里 `import Messages` —— 会毁掉以后换壳的可能
- ❌ 在 M1 用满意之前去接端侧模型 —— 先调 `PromptBuilder`，收益大得多
