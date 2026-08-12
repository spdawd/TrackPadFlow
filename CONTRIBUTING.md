# Contributing to TrackpadFlow

感谢你愿意改进 TrackpadFlow。项目优先接受范围清晰、能够验证、符合 macOS 原生交互习惯的变更。

## 开始之前

- Bug 与兼容性问题请使用仓库的 Bug Report 表单；
- 新功能请先提交 Feature Request，说明用户场景和手势冲突风险；
- 安全问题不要创建公开 Issue，请遵循 [SECURITY.md](SECURITY.md)。

## 本地环境

- macOS 14+
- Swift 6 / Xcode 16+
- 已授予构建副本必要的辅助功能和输入监控权限（仅在手势实测时需要）

```bash
./Scripts/verify.sh
```

构建缓存默认位于 macOS 用户缓存目录。也可以显式指定：

```bash
TRACKPADFLOW_ENV_ROOT=/path/to/cache ./Scripts/verify.sh
```

## 变更原则

- 保持 Event Tap 回调短小，不在回调内执行窗口枚举或耗时 AX 操作；
- 未按 `Command` 时不拦截普通滚动；
- 合成窗口、Panel 和反馈层不得激活或抢走焦点；
- 不新增遥测、网络请求或屏幕采集，除非先更新隐私文档并经过讨论；
- 保留 Finder 双击保护和辅助功能权限的系统确认边界；
- 不提交 `.build`、`build`、`dist`、DerivedData 或个人签名材料。

更多实现约束见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) 和 [docs/DEVELOPMENT_NOTES.md](docs/DEVELOPMENT_NOTES.md)。

## Pull Request

1. 从最新主分支创建短生命周期分支；
2. 只处理一个主题，避免混入格式化或无关重构；
3. 运行 `./Scripts/verify.sh`；
4. 在 PR 中说明行为变化、权限变化、验证步骤和截图（如涉及 UI）；
5. 用户可见变化请更新 README 或 CHANGELOG。

提交信息建议使用简短祈使句，例如：`Fix Finder double-click guard`。
