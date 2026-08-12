# Security Policy

## Supported versions

当前处于早期公开阶段，仅最新的 `0.1.x` 版本接收安全修复。请先确认问题在主分支或最新 Release 中仍然存在。

## Reporting a vulnerability

请不要为未修复漏洞创建公开 Issue。

优先使用仓库 **Security → Report a vulnerability** 的私密报告功能，并提供：

- 受影响版本和 macOS 版本；
- 复现步骤与预期影响；
- 是否涉及 Accessibility、Event Tap、签名、权限绕过或用户数据；
- 可行的缓解建议（如有）。

维护者会尽快确认报告。修复发布前，请避免公开利用细节。若仓库尚未启用私密漏洞报告，可先创建一个不包含敏感细节的 Issue，请求维护者提供私密联系方式。

## Security boundaries

TrackpadFlow 不应尝试修改 TCC 数据库、绕过系统授权、静默开启辅助功能权限或加载来源不明的可执行代码。发现相关行为请按漏洞处理。
