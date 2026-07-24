# mewmew UI 规格(Phase 1 三页骨架)

设计语言:克制现代(Stripe/Cloudflare 感),**纯色无渐变**;猫是唯一的情感元素,界面本身保持安静,把注意力让给猫和内容。

## 全局

- SwiftUI,iOS 17+,深浅色双主题(系统跟随)。
- 色板(纯色):
  - 背景 `#FFFFFF` / 深色 `#111113`
  - 卡片面 `#F6F6F7` / 深色 `#1B1B1F`
  - 主色(猫橘)`#F97316` —— 只用于主按钮、猫相关高亮
  - 文本主 `#18181B` / 深色 `#F4F4F5`;次级 `#71717A`
  - 语义色:提醒到期 `#DC2626`,完成 `#16A34A`
- 字体:系统 SF Pro;标题 `.title2.bold`,正文 `.body`,元信息 `.footnote`。
- 圆角 12,卡片无阴影(用 1px 描边 `#E4E4E7` / 深色 `#2A2A30`)。
- TabView 三 tab:猫(主页)· 记忆 · 我(Phase 6 前"我"页只放设置占位)。

## 页面 1:猫主页(默认落地页 + capture 入口)

结构自上而下:
1. 猫舞台(占屏 ~45%):猫形象居中(Phase 1 用静态占位图/SF Symbol `cat.fill` 大图标即可),下方一行猫的状态文案(如"小鱼干 ×3 · Lv.1")。
2. **大 capture 按钮**:通宽圆角矩形,主色填充,文案"记一下…";按下弹出 capture sheet。
3. "今天"区:今日到期提醒 + 到期卡片数量的两枚小结卡(横排),点击跳记忆列表相应过滤。

Capture sheet(Phase 1 仅文本,语音 Phase 2):
- 全高 sheet,顶部大号 TextField(placeholder"想记住什么?"),自动聚焦。
- 底部主按钮"让猫记住";Phase 1 直接按 note 入库(LLM 分流 Phase 2 接入),成功后 sheet 收起 + 猫舞台弹出确认气泡"记住啦!"。

## 页面 2:记忆列表

- 顶部分段控件:全部 · 提醒 · 卡片 · 笔记(对应 kind 过滤,调 `list_memories`)。
- 行卡片:标题 + 元信息行(kind 图标 + 相对时间;reminder 显示 due 时间,过期红色)。
- reminder 行左滑"完成"(调 `complete_reminder`,toast"+1 小鱼干 🐟"),所有行左滑"删除"(软删)。
- 空态:小猫插画占位 + "还没有记忆,去记一下?"按钮 → 回猫主页 capture。

## 页面 3:设置占位

- 列表:App 版本、数据库路径(debug)、"清空数据"(debug only)。Phase 6 换成账号/订阅。

## Swift ↔ core 集成约定

- `MewmewCore` 单例持有(App 启动 `new(dbPath)`,db 放 Application Support)。
- 所有 core 调用走后台队列(core 全同步),UI 层 `@MainActor` 回写;封一层 `CoreClient` actor。
- `now` 参数由 Swift 侧 `Date().timeIntervalSince1970` 传入。

## Phase 1 验收(CI 快照)

- 三页快照测试(浅色+深色):猫主页含 capture 按钮、列表页含 3 条种子数据(每 kind 一条)、空态页。
- 手动链路:capture 输入文本 → 列表出现该条 → 左滑完成 → 猫主页鱼干 +1。
