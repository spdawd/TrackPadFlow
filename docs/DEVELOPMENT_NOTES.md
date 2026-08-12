# Historical Development Notes

> 本文保留项目迭代期间验证过的实现、性能和排障经验，供维护者参考。面向用户的安装与使用说明请阅读仓库根目录 `README.md`。文中的 `<repo-root>` 与 `<cache-root>` 是通用占位路径。

# TrackpadFlow

一个使用 SwiftUI + AppKit 的 macOS 菜单栏 App，用 Command + 两指手势控制窗口和工作场景：

- 菜单栏驻留：设置面板从菜单栏图标弹出，点击外部收起，不依赖独立窗口找回
- 按住 Command + 两指右滑：最小化当前窗口
- 按住 Command + 两指左滑：恢复右滑压入栈中的栈顶窗口
- 连续右滑 A、B、C 后，连续左滑按 C、B、A 的顺序恢复
- 可拖动“触发步长（左右共用）”调整手势灵敏度
- 右滑收起的窗口会进入恢复栈，左滑只恢复栈顶的一个窗口
- 支持“反转横向方向”开关
- 双击端点框选：起点双击后可用双指滚动，终点双击确认后通过 Shift-click 扩展选区；普通单点会原样放行并取消等待，Finder 与起点附近的连续双击具有原生放行保护
- 可在设置面板调整“双击窗口”，用来适配不同的轻点节奏
- 可选监听全局鼠标左键点击，并在点击位置显示短暂白色半透明波纹反馈
- 使用 Command + CGEventTap 拦截手势期间的横向滚动，减少应用内横向手势冲突

## 设计哲学

TrackpadFlow 遵循一种“安静地恢复状态”的 macOS 式设计：让用户感到系统自然回到了工作状态，而不是看到应用在执行一串操作。

- 快照记录的是当前实际可见的工作画面，不追踪完全被遮挡的后台窗口。
- 恢复只修改必要的位置和尺寸，避免逐个唤醒应用、反复抢焦点和视觉闪现。
- 一次手势只产生一次最终焦点切换；能由系统原生窗口能力完成的动作，不叠加额外动画。
- 反馈克制、短暂、可关闭；默认不打断用户正在进行的工作。
- 优先选择轻量的 AppKit、Accessibility、Core Animation 能力，避免为了装饰引入持续运行的高成本效果。

## 视觉资产

- `Resources/TrackpadFlow-logo.png`：高清主视觉，可用于产品物料和设置页面。
- `Resources/TrackpadFlow.icns`：由主视觉生成的 macOS 多尺寸应用图标，打包脚本会自动放入 `.app`。

## 构建、安装和启动

遵循工作区里 BatteryBar 的 Swift Package + 手工 `.app` 流程：

```bash
cd <repo-root>
./Scripts/build_app.sh
open ./build/TrackpadFlow.app
```

也可以直接运行：

```bash
./Scripts/run_app.sh
```

SwiftPM 编译缓存不放在项目目录。`Scripts/build_app.sh` 固定使用：

```text
<cache-root>/TrackpadFlow/.build
```

可通过 `TRACKPADFLOW_ENV_ROOT` 覆盖 `environment` 根目录，但仍应保持 `<环境根>/TrackpadFlow/.build` 的 App 隔离结构。`apps/TrackpadFlow/build` 只保存约 3 MB 的最终 `.app`，可以随时重新生成；不要在项目根重新创建 `.build`，也不要把 SwiftPM 缓存打进交付包。

需要彻底清空编译缓存时，只删除上面的 TrackpadFlow 专属目录，随后运行构建脚本自动重建；不得删除整个共享 `environment`：

```bash
/usr/bin/swift package \
  --package-path <repo-root> \
  --scratch-path <cache-root>/TrackpadFlow/.build \
  reset
./Scripts/build_app.sh
```

Swift/Clang 的 `.pcm` 模块缓存记录绝对路径，不能把项目里的旧 `.build` 直接 `mv` 到新位置继续使用；迁移时必须 reset 旧缓存，并在新的 scratch path 干净重建。

需要辅助功能权限的日常使用版应先复制到稳定路径，再从该路径授权和启动：

```bash
pkill -x TrackpadFlow || true
/usr/bin/ditto ./build/TrackpadFlow.app /Applications/TrackpadFlow.app
codesign --verify --deep --strict /Applications/TrackpadFlow.app
open -n /Applications/TrackpadFlow.app
```

不要给 `build/TrackpadFlow.app` 授权后又改从 `/Applications` 启动，也不要在授权后用不同签名覆盖正式副本。路径、Bundle Identifier 和代码签名共同构成排障时必须核对的应用身份。

## 首次使用

窗口控制使用 macOS Accessibility API；Command + 滚动的全局拦截使用可修改事件的 `CGEventTap`，因此系统还可能要求“输入监控”权限。第一次打开菜单栏面板时，点击“一键申请并打开系统设置”：App 会调用 `AXIsProcessTrustedWithOptions` 发出系统请求并跳转“隐私与安全性 → 辅助功能”，用户只需在列表中亲自开启 TrackpadFlow。辅助功能负责 AX 窗口动作；如果随后显示“需要输入监控”，再点击对应入口开启输入监控。

App 未就绪时每秒刷新权限并重试 Event Tap；当 `AXIsProcessTrusted()` 为真且 Event Tap 创建成功后，轮询会停止，避免永久定时唤醒。系统设置的非选中窗口会把开关绘制成灰色，不能仅凭截图颜色判断权限；应以 `AXIsProcessTrusted()` 和 `eventTap != nil` 为真实状态。

macOS 不允许普通 App 静默把自己写入 TCC 授权库。所谓“一键添加”只能完成“发出系统请求 + 打开正确设置页 + 自动刷新结果”，最后的开关必须由用户或设备管理策略确认。禁止直接修改 TCC 数据库。未点击申请按钮前不自动弹窗，也不持续轮询；发出申请后才临时轮询授权结果。

## 实现边界

App 使用 CGEventTap 监听滚动和鼠标左键按下事件。Command 按住期间会吞掉整段触控板滚动，只有其中的横向位移用于累计并达到触发步长后执行窗口动作，避免前台应用启动自己的横向手势；未按 Command 的普通滚动不会被拦截。鼠标点击事件始终原样传递给前台应用，反馈通过不激活、忽略鼠标事件的透明浮层绘制，因此不会改变系统焦点。macOS 公共事件 API 不会可靠地提供“当前事件一定来自两根手指”的字段，因此普通触控板两指横滑是目标用法，其他连续横向滚动设备也可能触发；Command 模式下其他带横向位移的滚动设备也可能触发，应以目标设备和修饰键作为使用边界。

如果系统的横向滚动方向与手指移动方向相反，可以在菜单里打开“反转横向方向”。

左滑不再扫描或排序所有后台窗口，只处理由右滑产生的恢复栈；隐藏应用和 TrackpadFlow 自己的窗口不会被压栈。
- 左滑时会取消栈顶窗口的最小化并将它置前
- 右滑后会把焦点转移给视觉层级最上方的剩余窗口，避免系统出现无逻辑焦点状态
- 可拖动“触发步长（左右共用）”调整手势灵敏度
- 必须按住 Command 才会识别和拦截手势；Command 按住期间整段触控板滚动由 TrackpadFlow 独占
- Event Tap 被系统禁用时会自动重新启用，并在菜单栏显示需要输入监控权限
- 左滑恢复使用 LIFO 栈，只读取栈顶目标，避免重复扫描全部 Accessibility 窗口

## 全局点击视觉反馈

鼠标左键点击反馈采用“每次点击一个小型透明 Overlay”的结构：

- `CGEventTap` 只负责发现全局 `leftMouseDown`，原事件继续传递给前台应用。
- 每次点击使用 AppKit 的屏幕坐标创建一个以点击点为中心的不激活、鼠标穿透 `NSPanel`，避免全屏坐标换算偏移。
- `MouseClickFeedbackView` 只使用一个实心 `CAShapeLayer`：白色半透明填充、无外环、无高光、无回缩，单向向外扩散并淡出。
- 默认动画约 0.48 秒；开启“减少动态效果”时缩短为约 0.18 秒。最多保留一个反馈 Panel，快速连续点击不会堆积图层。
- 会读取“减少动态效果”系统设置，必要时切换到更短、更轻的反馈。

这套实现用实心半透明层近似玻璃质感，不使用 `NSVisualEffectView/.behindWindow`，也不采集或扭曲其他 App 的屏幕像素。真正的折射水波需要 `ScreenCaptureKit + Metal`，会引入屏幕录制权限、GPU 开销和额外延迟，暂不作为基础模式。

## 当前代码职责

```text
TrackpadFlowApp.swift
  AppDelegate → NSStatusItem + NSPopover，持有 GestureController
GestureController.swift
  权限、CGEventTap、Command 状态、手势累计、冷却、端点框选状态机
WindowController.swift
  AX 窗口最小化/恢复、LIFO 栈、场景快照、窗口匹配和层级恢复
MouseClickFeedback.swift
  鼠标点击位置的轻量 Core Animation 反馈
SnapshotFeedback.swift
  场景保持/恢复结果的非激活提示
Views.swift
  SwiftUI 设置面板，只展示状态并修改参数
```

边界必须保持清楚：Event Tap 回调把输入翻译成动作，`WindowController` 执行跨应用窗口业务，View 不枚举窗口、不直接持有 AX 对象。耗时的 AX/窗口枚举通过 `DispatchQueue.main.async` 离开同步 Event Tap 回调，防止 macOS 因回调超时禁用 Tap。

## 菜单栏生命周期：不要再回退

当前实现刻意对齐 BatteryBar，使用 `NSApplicationDelegateAdaptor` + `NSStatusBar.system.statusItem` + `NSPopover`，不是 `MenuBarExtra`：

- `AppDelegate` 必须强引用 `NSStatusItem` 和 `NSPopover`；局部变量会被释放，图标会消失。
- `LSUIElement=true` 表示没有 Dock 图标和普通主窗口；菜单栏按钮是找回设置界面的唯一常驻入口。
- Popover 使用 `.transient`，点外部自动收起；状态栏按钮使用系统模板符号，交给 macOS 处理尺寸、深浅色和排列，不绘制自定义右上角悬浮窗。
- 创建顺序保持为：先构造 `GestureController`，再建立 Status Item，最后把控制器注入 SwiftUI Popover。
- 菜单栏图标是否可见与辅助功能是否授权是两套独立状态，不能用其中一个推断另一个。

曾出现旧 Bundle Identifier 的菜单栏注册状态损坏：同一二进制使用旧 ID 时 Status Item 位于屏幕外/被 Control Center 隐藏，换新 ID 后立即恢复。遇到类似问题，先用同一二进制只替换 Bundle Identifier 做 A/B 测试；确认是身份缓存后再更换 ID。更换 ID 会同时产生新的 TCC 身份和 `UserDefaults` domain，必须迁移设置并重新授权，不能只改 `Info.plist` 一处。

## 手势状态机规约

Event Tap 位于 `.cgSessionEventTap` + `.headInsertEventTap`，使用 `.defaultTap`。键盘侧以 `flagsChanged` 为主，同时保留 `keyDown/keyUp` 作为 Command 到达时序异常的可靠性兜底；回调拿到普通按键后立即按 keycode 过滤，只更新左右 Command。鼠标侧仅在“点击反馈”或“端点框选”至少一项开启时订阅左键按下/抬起，两项都关闭后会重建更小的 Event Tap。空闲时不监听 `mouseMoved`。

Command 是显式模态键：

- 未按 Command 的滚动原样传给前台 App。
- 一旦识别 Command + 滚动，整段横向、纵向、零横向样本和惯性尾部都吞掉，不能只吞达到阈值的那个事件；否则 Safari/WPS 等前台 App 已经启动自己的手势。
- Command 的按下状态同时参考左右 Command keycode、事件 flags、`CGEventSource` 和 `NSEvent.modifierFlags`，减少 flagsChanged 丢样造成的失灵。
- 阈值一旦达到，动作就成为一次性已提交命令，与用户何时松开 Command 解耦；窗口恢复不能依赖持续长按。
- 一个物理滑动只触发一个动作。新的 scroll-began 才能开始下一条命令；结束、取消、惯性和 0.45 秒尾部防抖共同清理状态。
- 预触发累计超时为约 0.32 秒，动作冷却为 0.3 秒，Command 松开保留约 0.6 秒尾部宽限。调整其中一个参数时必须回归“一来一回误触发”和“长按 Command 连续发多条独立手势”两种场景。
- Event Tap 被 `.tapDisabledByTimeout` 或 `.tapDisabledByUserInput` 禁用时立即重新启用。

横向左右共用可调 `triggerThreshold`；方向由“反转横向方向”映射。纵向场景手势使用独立的较小最低阈值，以实际 `pointDeltaAxis1` 优先，避免触控板纵向位移被 `fixedPtDelta` 缩小后不灵敏。自然滚动会让事件轴方向与手指方向相反，界面文案必须按用户手指方向描述并用实机校验。

## 窗口恢复栈

窗口轮转不是全局扫描器，而是明确的 LIFO 栈：

1. 右滑读取前台 regular App 的 focused/main window。
2. `AXMinimized=true` 成功后才把窗口压栈。
3. 立即从 `CGWindowList` 中找视觉层级最高的其他普通 App，并依次尝试 activate、AXMain、AXFocused、AXRaise，避免最小化后系统失去逻辑焦点。
4. 左滑只弹出一个栈顶窗口；成功后结束，失败则把目标放回栈顶，已退出 App 直接跳过。

不要恢复成“每次扫描所有后台窗口并按最近使用排序”的版本。它会在两个窗口之间反复、唤醒不属于本次操作的窗口，并增加 AX 枚举延迟。栈只保存在内存，App 重启后清空。

## 工作场景快照

Command + 两指下滑保持场景，Command + 两指上滑恢复。它保存的是当前视觉工作面，不是单个 focused window，也不是所有后台窗口：

- `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 提供前到后的 layer-0 窗口及 z-order。
- 从前向后做矩形遮挡扣除；窗口至少有 1,500 平方点或 20% 面积可见才进入快照。完全被遮挡或只露细边的后台窗口不保存。
- 通过 PID、标题和与 CG frame 的距离匹配 AX window，保存 application、title、frame、z-order。
- 恢复时只处理仍存在的目标；必要时取消最小化，位置/尺寸变化超过 1 点才设置 frame，减少无意义抽搐。
- 所有窗口准备好后按 back-to-front 顺序逐个激活/提升，最后一次激活自然留下最前窗口。一次手势启动整套恢复，Command 中途松开不能终止队列。
- 反馈只出现一次简短的保存/恢复结果，不显示保存窗口数量，不为每个窗口重复弹提示。

`AXRaise` 不能代替跨应用 activation：未激活 App 的窗口可能仍在当前 App 后面；也不能并发乱序激活多个 App，否则最终层级不确定。恢复是短序列，但触发必须是一次性的。

## 双击端点框选

端点框选只监听两端的双击，不尝试模拟“二次轻点后长按拖动”：

- 起点双击成功后直接进入等待；期间双指滚动不会取消状态。
- 终点的第一次点击先缓冲 down/up，不立即交给前台 App；窗口期内同一区域出现第二次轻点才确认终点。
- 确认时把第一组终点点击改成一次 Shift-click 回放，吞掉用于确认的第二组点击，随后立即退出等待，避免持续拖选。
- 如果第二次点击只是普通单点、超时、移动过大或按压过久，原点击必须无损回放并取消等待，不能误杀正常点击。
- Finder 不进入端点框选状态机；若等待期间再次点击起点 40 点范围内，也会先退出等待并原样放行，从而保证文件和文件夹的同一区域连续双击正常工作。
- 当前轻点最长约 0.22 秒，同点容差 40 点；可调双击窗口为 0.30–3.00 秒。
- 终点使用 AX `kAXRangeForPositionParameterizedAttribute` 在 24 点半径、6 点步长内寻找附近可选文本位置；找不到就使用原坐标。吸附是降级增强，不能成为完成框选的前置条件。
- 回放事件必须设置重入保护，否则 App 自己 post 的事件会再次进入 Event Tap，形成递归缓冲。

## 权限、签名与安装排障

当前 Bundle Identifier 是 `com.jingxuanpan.trackpadflow.menubar`。`Info.plist` 的 Bundle Identifier、`codesign` identifier、实际运行进程路径和设置面板里选中的 `.app` 必须指向同一个身份。

本地脚本使用标准 ad-hoc 签名：

```bash
codesign --force --deep --sign - \
  --identifier com.jingxuanpan.trackpadflow.menubar \
  build/TrackpadFlow.app
```

不要恢复 `designated => identifier "..."` 这种只约束 Bundle Identifier、没有 anchor 或 cdhash 的自定义 requirement。它虽然可能通过 `codesign --verify`，但本机实测“辅助功能”文件选择器会在点击“打开”后静默拒绝加入。标准 ad-hoc 签名的 designated requirement 是 cdhash，因此每次二进制变化都可能需要重新授权；长期开发应使用稳定的 Apple Development/Developer ID 签名，而不是伪造宽松 requirement。

准备发布 GitHub Release 时，建议使用稳定的 `Developer ID Application` 身份签名，并完成 hardened runtime、notarization 和 stapling；同时保持 Bundle Identifier `com.jingxuanpan.trackpadflow.menubar` 不变。开发脚本产生的 ad-hoc 包适合本机测试，不适合作为长期公开更新渠道，因为每次二进制变化都会产生新的 cdhash，用户可能被迫重新授权辅助功能。

添加权限没反应时按这个顺序处理，不要反复截图猜测：

1. `codesign --verify --deep --strict --verbose=2 /Applications/TrackpadFlow.app`。
2. `codesign -d -r- /Applications/TrackpadFlow.app`；标准 ad-hoc 应显示 cdhash requirement，不应只显示 identifier。
3. 确认运行的是 `/Applications/TrackpadFlow.app/Contents/MacOS/TrackpadFlow`，不是 build 中的另一个副本。
4. 只在身份确实陈旧时执行 `tccutil reset Accessibility com.jingxuanpan.trackpadflow.menubar`，它会撤销该身份现有授权。
5. 重新打开“辅助功能”，通过 `+` 选择 `/Applications/TrackpadFlow.app`，完成系统认证并开启开关，然后重启 App。
6. 用运行进程验证 `AXIsProcessTrusted()`；不要把“列表里有条目”当成最终成功。

本次验证可用：

```bash
pid=$(pgrep -x TrackpadFlow | head -1)
/usr/bin/lldb -p "$pid" \
  -o 'p (bool)AXIsProcessTrusted()' \
  -o detach -o quit
```

期望值是 `(bool) true`。Accessibility 为真但界面仍显示“需要输入监控”时，问题在 Event Tap 创建，不要继续重置辅助功能。

## 性能与视觉验收

- 空闲状态不做窗口轮询、不枚举 AX 窗口、不监听鼠标移动；权限轮询就绪后停止。
- 普通键盘输入会经过 Event Tap，但只做一次 keycode 比较便立即返回；这是为可靠识别 Command 支付的小成本，不能再用滚动前置快速放行替代。
- 每个滚动样本都先完成 Command 的多源判断，再决定是否放行。不要在物理键状态兜底之前用 `event.flags` 单独快速返回；部分触控板样本可能没有携带该 flag。
- 横向和纵向都优先累计 `pointDelta`，只有 point delta 缺失时才回退到 `fixedPtDelta`/整数 delta；否则共享阈值在不同方向上的手感不一致。
- 点击反馈复用同一个 72×72 `NSPanel` 和 View，通过 presentation generation 防止旧清理任务关闭新动画；禁止恢复为“每次点击创建一个窗口”。
- 开启 macOS 低电量模式时，点击反馈自动使用与“减少动态效果”相同的短动画路径。
- Event Tap 回调只累计数值、更新小状态并安排动作，不能同步做场景恢复。
- 点击反馈最多一个 72×72 非激活 Panel，只用 Core Animation 实心层；不恢复毛玻璃、外环、多波纹或全屏透明窗口。
- 所有反馈窗口必须 `ignoresMouseEvents=true`、不激活、跨 Space 可见，且以目标屏幕坐标为中心。坐标错误时优先检查 CG 顶部原点与 AppKit 底部原点的转换，禁止用“固定左下角偏移”补丁。
- 场景反馈使用 generation token，旧的延迟清理不能误关新提示。
- 尊重“减少动态效果”；动画约 420–520 ms，快速消失，不妨碍连续操作。

2026-08-05 的当前版本在权限就绪、Popover 关闭且系统空闲时，连续 6 次 `top` 采样均为 0.0% CPU、4 个线程、power 0.0；这只是本机开发基线，不是跨设备性能承诺。回归时更应观察打字、连续滚动和快速点击期间的唤醒，而不是只看静置瞬时 CPU。

## 每次改动后的回归清单

1. release 构建和 `codesign --verify --deep --strict` 通过。
2. 项目根不存在 `.build`，SwiftPM 缓存位于 `environment/TrackpadFlow/.build`。
3. 从 `/Applications` 启动，菜单栏出现一个正常系统状态项，关闭 Popover 后仍能从菜单栏找回。
4. 控制面板同时显示 Accessibility 和 Event Tap 的真实状态。
5. Command + 右滑连续最小化 A/B/C，再左滑按 C/B/A 各恢复一个；最小化后焦点落到视觉最上层窗口。
6. 一次物理滑动只执行一次，松开 Command 不会撤销已提交动作；持续按住 Command 可以做多次彼此独立的滑动。
7. Command + 下滑保存多窗口场景，上滑一次恢复完整可见组合；不需长按、不重复弹三次提示、不只恢复一个窗口。
8. 起点双击、滚动、终点双击完成一次跨页扩选；原地双击（未滚动）不进入框选；普通单点无损放行并退出框选状态。
9. 快速点击反馈不抢焦点、不挡鼠标、无外环且空闲能耗恢复正常。
10. Safari、WPS 等前台 App 在 Command 手势期间不再收到自己的滚动/导航手势；不按 Command 时滚动完全正常。
