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
- ✅ **Phase 0.5**:TestFlight 全链路通。fastlane `beta` lane(API key → match → build_app → upload)+ macos-26 runner。**build 1 已上传,Apple 侧 VALID**。App 记录与 Bundle ID 已建(app id 6794423533)。
- ✅ **Phase 2**:core `reclassify_memory` + Worker `/v1/parse` + iOS 语音 capture。**Worker 线上 https://mewmew-api.pp-account.workers.dev,生产实测 6/6 分类正确、时间落在调用方时区**。
- ⏳ **Phase 3 起**:本地通知提醒 + 问猫召回,未开工。

## 线上资源

| 资源 | 值 |
|---|---|
| Worker | https://mewmew-api.pp-account.workers.dev(`POST /v1/parse`) |
| KV(每日配额) | `RATE_LIMIT` = ead390002d5a48f7b664d0c22e45a96e |
| Worker secrets | `APP_TOKEN`、`DEEPSEEK_API_KEY` |
| App Store Connect | app id 6794423533,Bundle ID 45ZYJ5953A |
| 重配签名/Worker | `scripts/bootstrap-signing.sh` / `scripts/bootstrap-worker.sh` |

## 规格文档
docs/core-spec.md · docs/ui-spec.md · docs/ios-ci-spec.md · docs/worker-spec.md
(worker-spec.md 里的 system prompt 是实测验证过的基线,勿随意重写)

## 坑 / 注意
- UniFFI modulemap 需从 `mewmew_coreFFI.modulemap` 复制成 `module.modulemap` 才能被 Swift import(build-swift.sh 已处理)。
- 私有仓 GHA macOS 分钟 10× 计费,TestFlight lane 只在 tag/手动触发。
- core API 时间由调用方传 now(unix 秒),core 不读系统时钟。
- **`INFOPLIST_KEY_<自定义键>` 不会进 Info.plist**(CI 实证)。app token 走 `scripts/inject-app-token.sh` 写 `BuildConfig.swift` 编译期注入,CI 有断言防止静默漏配。
- **分类失败一律静默降级**是刻意设计(capture 不能失败),代价是配置错误也无声无息 —— 所以设置页有"智能分类"状态行、CI 有 token 断言。
- Apple 要求 iOS 26 SDK 才收包(macos-14 runner 的 Xcode 15 会被拒);app 图标/启动画面/屏幕方向缺一个都会被上传校验拦下。
- Cloudflare 会挡 `Python-urllib` 默认 UA(403),写监控脚本记得设 User-Agent。
