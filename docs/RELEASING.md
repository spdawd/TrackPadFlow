# Releasing

GitHub Release 应基于 Git tag，并附带可安装 App、SHA-256 校验文件和清晰的版本说明。

## 1. Prepare

1. 更新 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 与 `CFBundleVersion`；
2. 更新 `CHANGELOG.md`；
3. 运行 `./Scripts/verify.sh`；
4. 在干净账户或测试 Mac 上验证权限、窗口手势和升级行为。

## 2. Sign

公开分发应使用 `Developer ID Application`：

```bash
TRACKPADFLOW_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
  ./Scripts/package_release.sh
```

脚本会启用 hardened runtime 和 secure timestamp，并在 `dist/` 生成 ZIP 与 SHA-256 文件。不要把 ad-hoc 包作为长期公开更新渠道。

## 3. Notarize

先使用 Xcode 的 `notarytool` 保存凭据：

```bash
xcrun notarytool store-credentials TrackpadFlowNotary
```

提交 ZIP 并等待结果：

```bash
xcrun notarytool submit dist/TrackpadFlow-vVERSION-macOS.zip \
  --keychain-profile TrackpadFlowNotary \
  --wait
```

成功后把票据附加到 `.app`，重新生成最终 ZIP 与校验文件：

```bash
xcrun stapler staple build/TrackpadFlow.app
xcrun stapler validate build/TrackpadFlow.app
./Scripts/package_release.sh --skip-build
```

## 4. Gatekeeper verification

```bash
codesign --verify --deep --strict --verbose=2 build/TrackpadFlow.app
spctl --assess --type execute --verbose=4 build/TrackpadFlow.app
```

## 5. Tag and publish

```bash
git tag -s vVERSION -m 'TrackpadFlow vVERSION'
git push origin vVERSION
```

在 GitHub Releases 中选择该 tag，使用自动生成的 Release Notes 作为草稿，再补充：

- 支持的 macOS 与 CPU 架构；
- 安装和权限步骤；
- 升级是否需要重新授权；
- 已知问题；
- ZIP 的 SHA-256。

上传 `dist/` 中最终的 ZIP 与 `.sha256`。发布后从 GitHub 下载一次并重新验证 Gatekeeper 和权限流程。
