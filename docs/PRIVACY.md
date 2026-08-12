# Privacy

TrackpadFlow 的设计目标是让所有输入和窗口处理停留在本机。

## Collected data

TrackpadFlow 不收集或上传个人数据。项目不包含：

- 网络客户端或远程 API；
- 账号、登录或云同步；
- 分析、遥测、崩溃上传或广告 SDK；
- 屏幕录制、截图或窗口像素采集；
- 点击历史、窗口标题历史或应用使用历史。

## Local data

以下偏好通过 macOS `UserDefaults` 保存在本机：

- 手势触发步长；
- 左右方向反转；
- 点击反馈开关；
- 双击端点框选开关与时间窗口。

窗口恢复栈和场景快照只存在于运行进程内存中，退出 TrackpadFlow 后清空。

## Sensitive APIs

Accessibility 和 Event Tap 可能观察到系统级窗口与输入事件。TrackpadFlow 只处理实现用户主动触发功能所需的最少字段，不持久化原始事件，不把数据发送到其他进程或网络。

## Future changes

若未来版本引入网络、更新检查、崩溃报告、屏幕采集或任何数据上传，必须在合并前更新本文件、README 和用户界面说明。
