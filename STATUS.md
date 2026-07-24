# mewmew STATUS

记忆猫 iOS App。口述/键入 → 猫替你记(提醒+召回)/帮你背(FSRS)/养成对抗通知疲劳。

**技术栈**:SwiftUI(UI)+ Rust `mewmew-core`(UniFFI 绑定,SQLite/FSRS/猫状态机)+ CF Worker(LLM 代理/OTP/同步)。iOS-only。
**仓库**:YSKM523/mewmew(私有)。证书仓 YSKM523/mewmew-certs。
**无 Mac**:一切 iOS 编译/测试/分发走 GitHub Actions macOS runner(`.github/workflows/ios.yml`)。
**执行分工**:实现委托 codex(gpt-5.6-sol high);Claude 负责验收 + 前端设计;生产部署/提审人工确认。
**定价**:Pro $4.99/月(StoreKit 2)。**Bundle ID**:com.tensorproxies.mewmew。**App Store 显示名**:「mewmew — 记忆猫」。

## 当前进度(2026-07-24)

- ✅ **Phase 0**:定名 mewmew;上架显示名「mewmew — 记忆猫」;定价 $4.99;仓库已建。
- ✅ **Phase 1**:骨架落地并 CI 全绿。Rust core(6 测试)+ SwiftUI 三页(猫主页/记忆列表/设置)+ UniFFI 链路 + 快照测试。commit 7d8bbb3。**macOS runner 真 Xcode 编译通过,快照渲染正确**。
- 🟡 **Phase 0.5**:CI 链路通;签名 secrets P8/KEY_ID/ISSUER_ID 已设并 API 实测有效;TEAM_ID 待用户自设(可选)。**未做**:fastlane TestFlight lane 实装 + ASC 里注册 mewmew app。
- ⏳ **Phase 2 起**:统一 capture(SFSpeechRecognizer + Worker LLM 分流)未开工。规格见 docs/worker-spec.md(先本地落库再 LLM 升级分类,DeepSeek max_tokens≥1024)。

## 规格文档
docs/core-spec.md · docs/ui-spec.md · docs/ios-ci-spec.md · docs/worker-spec.md

## 坑 / 注意
- UniFFI modulemap 需从 `mewmew_coreFFI.modulemap` 复制成 `module.modulemap` 才能被 Swift import(build-swift.sh 已处理)。
- 私有仓 GHA macOS 分钟 10× 计费,TestFlight lane 只在 tag/手动触发。
- core API 时间由调用方传 now(unix 秒),core 不读系统时钟。
