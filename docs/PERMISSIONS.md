# Permissions

TrackpadFlow 使用 macOS 官方 Accessibility 与 Core Graphics Event Tap API。权限由系统 TCC 管理。

## Accessibility

用途：

- 读取当前前台窗口；
- 最小化、取消最小化和提升窗口；
- 恢复窗口位置、尺寸与层级。

在 TrackpadFlow 面板点击“一键申请并打开系统设置”。应用会调用 `AXIsProcessTrustedWithOptions` 发出请求并打开：

```text
系统设置 → 隐私与安全性 → 辅助功能
```

随后由用户亲自开启 TrackpadFlow。macOS 不允许应用替用户点击开关，也不允许普通应用静默写入 TCC 数据库。

## Input Monitoring

用途：创建可修改的 Event Tap，在 Command 手势期间阻止同一滚动事件继续触发 Safari、Finder 或其他应用的手势。

如果 Accessibility 已开启但面板显示“需要输入监控”，打开：

```text
系统设置 → 隐私与安全性 → 输入监控
```

开启 TrackpadFlow 后重启应用。

## Stable installation identity

先将应用移动到 `/Applications`，再授权并从该路径启动。TCC 会结合应用路径、Bundle Identifier 和代码签名判断身份。

- Bundle Identifier：`com.jingxuanpan.trackpadflow.menubar`
- ad-hoc 开发签名使用 cdhash 作为身份的一部分；二进制变化后可能需要重新授权；
- Developer ID 签名具有稳定的指定要求，更适合公开更新。

## Diagnostics

验证安装包签名：

```bash
codesign --verify --deep --strict --verbose=2 /Applications/TrackpadFlow.app
codesign -d -r- /Applications/TrackpadFlow.app
```

确认实际运行路径：

```bash
pgrep -fal '/Applications/TrackpadFlow.app/Contents/MacOS/TrackpadFlow'
```

只有在旧身份确实卡住时，才撤销 TrackpadFlow 自己的 Accessibility 记录：

```bash
tccutil reset Accessibility com.jingxuanpan.trackpadflow.menubar
```

该命令会撤销现有授权，执行后必须重新确认。不要删除整个 TCC 数据库，也不要重置其他应用权限。
