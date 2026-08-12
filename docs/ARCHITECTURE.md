# Architecture

TrackpadFlow 是一个单进程、原生 macOS 菜单栏应用。运行时不需要服务端、数据库或第三方框架。

## Components

```text
AppDelegate
  ├─ NSStatusItem + NSPopover
  └─ GestureController
       ├─ CGEventTap：Command、滚动和可选鼠标点击
       ├─ WindowController：Accessibility 窗口操作
       ├─ MouseClickFeedbackController：点击反馈
       └─ SnapshotFeedbackController：场景反馈
```

### TrackpadFlowApp.swift

创建菜单栏状态项和 SwiftUI Popover。应用设置 `LSUIElement=true`，不显示 Dock 图标，也不会因关闭 Popover 而退出。

### GestureController.swift

- 维护 Accessibility 与 Event Tap 状态；
- 从多个来源确认 Command 物理状态；
- 累计横向、纵向滚动并执行阈值判断；
- 吞掉已进入 Command 手势的完整滚动序列，避免前台应用同时响应；
- 管理端点双击框选、冷却和超时；
- 将耗时窗口动作派发到 Event Tap 回调之外。

### WindowController.swift

- 最小化前台窗口并压入 LIFO 恢复栈；
- 恢复栈顶窗口并纠正焦点；
- 使用 `CGWindowListCopyWindowInfo` 与 Accessibility 匹配当前可见窗口；
- 保存窗口 frame 与 z-order；
- 按确定的 back-to-front 顺序恢复场景。

### Feedback controllers

反馈层使用不激活、鼠标穿透的 AppKit Panel。点击反馈由一个 `CAShapeLayer` 完成，不采集屏幕像素，不使用持续渲染循环。

## Event flow

```text
Physical input
  → CGEventTap
  → Command state + axis accumulation
  → threshold / cooldown state machine
  → dispatch window command
  → Accessibility API
  → optional non-activating feedback
```

## Invariants

- 未按 Command 的普通滚动必须原样放行；
- Event Tap 回调不得执行窗口枚举、场景恢复或其他阻塞工作；
- 一次物理滑动最多提交一个窗口命令；
- 命令提交后不依赖用户继续按住 Command；
- TrackpadFlow 的反馈窗口不得成为 key/main window；
- 所有 TCC 权限都由系统和用户决定，代码不得修改授权数据库；
- 空闲状态不运行显示循环，也不枚举窗口。

## Data and network

应用没有网络模块。偏好设置通过 `UserDefaults` 保存在本机；窗口恢复栈与场景快照只保存在当前进程内存中，退出应用后清空。
