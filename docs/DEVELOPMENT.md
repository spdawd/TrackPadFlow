# Development

## Requirements

- macOS 14+
- Swift 6 / Xcode 16+
- zsh、codesign、PlistBuddy、ditto（macOS 自带）

## Build

```bash
./Scripts/build_app.sh
```

构建脚本执行 SwiftPM Release 构建、组装标准 `.app` 目录并签名。输出位于：

```text
build/TrackpadFlow.app
```

在原始多项目工作区中，SwiftPM scratch path 使用共享 `environment/TrackpadFlow/.build`。独立克隆时使用 `getconf DARWIN_USER_CACHE_DIR` 返回的用户缓存目录。也可以显式设置：

```bash
TRACKPADFLOW_ENV_ROOT=/path/to/cache ./Scripts/build_app.sh
```

不要直接移动已有 `.build` 缓存；Swift/Clang 模块缓存包含绝对路径，迁移缓存应清空后重新构建。

## Run and install

```bash
./Scripts/run_app.sh
./Scripts/install_local.sh
```

开发副本和 `/Applications` 副本是不同的 TCC 身份。需要完整手势验证时，只保留一个运行副本，并从稳定安装路径授权。

## Verify

```bash
./Scripts/verify.sh
```

验证包括：

- `swift package describe`；
- Release 构建和 `.app` 组装；
- `Info.plist` 语法与 Bundle Identifier；
- 深度代码签名验证；
- 构建产物中不存在意外的个人路径文件。

## Signing

默认使用 ad-hoc 签名：

```bash
./Scripts/build_app.sh
```

使用 Developer ID：

```bash
TRACKPADFLOW_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
  ./Scripts/build_app.sh
```

非 ad-hoc 身份会自动启用 hardened runtime 和 secure timestamp。不得使用仅约束 Bundle Identifier 的宽松自定义 designated requirement。

## Regression checklist

1. 菜单栏图标稳定显示，关闭 Popover 后仍能找回；
2. 未按 Command 时，横向与纵向滚动原样放行；
3. 按住 Command 可连续触发不同方向手势；
4. 一次滑动只提交一次命令；
5. 右滑 A/B/C 后左滑按 C/B/A 恢复；
6. 保存和恢复场景只出现一次反馈；
7. Finder 连续双击能正常打开文件夹；
8. 普通单点、起点双击和终点双击框选均无事件丢失；
9. 点击反馈不抢焦点，减少动态效果与低电量模式生效；
10. 空闲时 CPU 与 power 接近零。

更详细的历史实现与排障经验见 [DEVELOPMENT_NOTES.md](DEVELOPMENT_NOTES.md)。
