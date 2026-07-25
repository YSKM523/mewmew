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
- ✅ **Phase 3**:提醒 + 召回闭环。core `pending_reminders`/`snooze_reminder`/中文 FTS `search_for_recall`;Worker `/v1/recall` **已上线实测**;iOS 通知调度(全量重放,上限 56)+ 猫口吻通知(「记下了」/「等会儿」)+ 问猫 UI。
- ✅ **Phase 4**:间隔重复闭环。core FSRS(`rs-fsrs` 1.2.1,migration v3,`due_cards`/`review_card`/`next_card_due_at`)+ iOS 考问会话(两步揭晓、三档评分)+ 复习通知(安静时段顺延)。
- ✅ **Phase 5**:猫养成。core 状态机(migration v4,`feed_cat`/`cat_status_at`/`unlocked_outfits`/`set_outfit`)+ iOS 猫主页(SwiftUI 绘制,三种 mood、喂猫、等级进度、装扮)。
- ⏳ **Phase 6 起**:账号(邮箱 OTP)+ D1 同步 + StoreKit 2 订阅,未开工。

## 线上资源

| 资源 | 值 |
|---|---|
| Worker | https://mewmew-api.pp-account.workers.dev(`POST /v1/parse`、`POST /v1/recall`) |
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
- **上传成功 ≠ 测试员能装**:构建的 `usesNonExemptEncryption` 为 null 时,API 仍报 `processingState=VALID`,但对测试员不可安装(网页显示"缺少合规信息"),邀请会以 `NO_INSTALLABLE_BUILDS` 失败。project.yml 已加 `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: false` 永久解决。
- TestFlight 还需要**测试组 + 测试员**才可见:内部组 `内部测试`(id 2d3878ff-3150-47d1-b4b8-afd7bc412c6f,hasAccessToAllBuilds),测试员 wukongkong07@gmail.com。内部组不能手动关联构建(422 是正常的,它自动含全部)。
- Apple 要求 iOS 26 SDK 才收包(macos-14 runner 的 Xcode 15 会被拒);app 图标/启动画面/屏幕方向缺一个都会被上传校验拦下。
- Cloudflare 会挡 `Python-urllib` 默认 UA(403),写监控脚本记得设 User-Agent。
- **中文召回**:FTS5 逐字建索引;查询要去掉功能词/疑问词(在/哪/吗…)再 AND,空结果时退化成 OR。裸关键词测试会掩盖问题——真实问法是"护照在哪"而不是"护照",回归测试在 `core/tests/recall_phrasing.rs`。
- **OR 兜底会有假阳性**(飞机→咖啡机),这是刻意的:检索多召回、模型守住不编造(已实测)。别当 bug 去"修"。
- iOS 本地通知 pending 上限 64,超出静默丢弃 → 只排 56 条并在设置页显示实际排期数。
- **Swift 并发隔离/协议遵循只能靠 CI 兜**(Linux 无编译器):@MainActor 类型不能直接当默认参数、实现了 delegate 方法≠声明了遵循。
- **`rs_fsrs::Card::new()` 读系统时钟,禁用**——手工构造 Card,时间由调用方传。确定性有测试守着(同输入必须同输出)。
- FSRS 间隔实测:新卡答 Good 后 10 分钟,再 4d→15d→48d→136d→351d。测试断言"递增"而非写死天数(参数升级会变)。
- **猫的心情必须在静止帧可辨**:只靠动画区分等于没做——用户开 app 第一眼是静止画面。现在 sleepy 闭眼、happy 睁大眼+尾巴翘起。
- **扁平几何画不出布料**:围巾试了三版(锤子/拐杖/锤子)都失败,换成铃铛项圈(靠轮廓识别)一次成功。装扮要选轮廓能表达的东西。
- **衰减不夺走任何东西**是产品承诺,由 `ten_days_of_decay_only_changes_mood` 测试守着,不是文档里一句话。
- **测试里别用裸下标**(`requests[0]`):断言失败会变成测试进程崩溃,带走同进程其他测试并伪装成"快照找不到参考",极难定位。用 `XCTUnwrap`。
