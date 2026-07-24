# mewmew 🐱

记忆猫 — iOS 快速交互记忆 App。口述/键入想记住的东西,猫管家替你记(提醒+召回)、帮你背(FSRS 间隔重复主动来考),养成机制对抗通知疲劳。

## 架构

- `core/` — Rust 核心 crate(`mewmew-core`):SQLite 数据层、FSRS 调度、猫状态机、同步引擎;UniFFI 生成 Swift 绑定。Linux 上 `cargo test` 全量可测。
- `ios/` — SwiftUI App(XcodeGen 生成工程):UI、SFSpeechRecognizer 语音、本地通知、StoreKit 2。
- `worker/` — CF Worker:LLM 解析代理(DeepSeek)、邮箱 OTP、D1 同步。
- `docs/` — 产品/技术规格。

## 构建

- Rust:`cd core && cargo test`
- iOS:无本地 Mac,构建走 GitHub Actions macOS runner + fastlane(见 `.github/workflows/`,Phase 0.5)。
