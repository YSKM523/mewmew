# iOS 工程 + 云构建规格(Phase 0.5 / Phase 1 iOS 侧)

无本地 Mac:一切 iOS 编译/测试/分发都在 GitHub Actions macOS runner 上完成。

## Xcode 工程(XcodeGen)

- 不提交 .xcodeproj,提交 `ios/project.yml`,CI 上 `xcodegen generate`。
- Target `Mewmew`(iOS 17.0+,SwiftUI App,Bundle ID `com.tensorproxies.mewmew`),Target `MewmewTests`(含快照测试)。
- Rust 集成:build phase 脚本调 `core/build-swift.sh` 产出 `MewmewCore.xcframework` + 生成的 Swift 绑定文件;工程链接该 xcframework。
- 快照测试用 `pointfree/swift-snapshot-testing`(SPM 依赖),浅色/深色各页一张,产物上传为 CI artifact 供验收查看。

## GitHub Actions(`.github/workflows/ios.yml`)

触发:push 到 main 且路径命中 `ios/**`、`core/**`、workflow 自身;或手动 `workflow_dispatch`。分两 job:

1. **rust-check(ubuntu,便宜,每次跑)**:`cargo test` + `cargo clippy -- -D warnings` + `cargo fmt --check`。
2. **ios-build(macos-14,贵,10× 计费,依赖 rust-check 通过)**:
   - 装 rust targets `aarch64-apple-ios aarch64-apple-ios-sim` + `xcodegen`;缓存 cargo + SPM。
   - `core/build-swift.sh` → `xcodegen generate` → `xcodebuild test`(模拟器,含快照)→ 上传快照 artifact。
   - **TestFlight 上传 job 单独拆开,仅 tag `v*` 或手动触发时跑**(控频省分钟):fastlane `build_app` + `upload_to_testflight`,签名走 App Store Connect API key(无 Mac 纯 CI 签名)。

## 签名(fastlane,无 Mac)

- `fastlane match` + 私有 certificates 仓(YSKM523/mewmew-certs),App Store Connect API key 走 GHA secrets:`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`、`MATCH_PASSWORD`、`MATCH_GIT_BASIC_AUTHORIZATION`。
- 首次:`match appstore` 在 CI 上跑一次生成证书(API key 权限需 App Manager)。

## 用户需提供(阻塞项)

1. Apple Developer Program 账号($99/年)已就绪与否;
2. App Store Connect API Key(.p8 + key id + issuer id);
3. GitHub 私有仓 mewmew + mewmew-certs 创建许可(gh 可代建)。

## 验收

- push → rust-check + ios-build 全绿,快照 artifact 可下载查看三页 UI;
- 手动触发 TestFlight lane → 用户 iPhone TestFlight 装上 app。
