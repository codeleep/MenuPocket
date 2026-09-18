# MenuPocket 版本发布

## 1. 版本规则

`VERSION` 是发行版本的唯一来源，例如 `0.2.0-alpha.1`。标签必须为 `v` 加完整版本号，工作流会检查两者一致。应用标准版本字段使用前三段数字，完整版本另存于 `MenuPocketVersion`，构建号来自 GitHub Actions 运行编号。

修改行为时更新 [CHANGELOG](../CHANGELOG.md)、教程和兼容性记录。Alpha 版本不承诺全部菜单栏应用兼容。

## 2. 合并前检查

CI 在 macOS 15 Apple Silicon 和 Intel 上分别执行检查、模型测试及本机架构构建；另外生成 Universal 包并上传构建产物，保留 14 天。Actions 使用固定提交版本，Dependabot 定期提出更新。

```sh
make check
make test
bash scripts/build.sh --arch universal --sign adhoc --output dist/release-check
bash scripts/package.sh dist/release-check
```

维护者还需在真实桌面验证授权、分组、单图标偏好、隐藏/恢复、菜单点击及退出恢复。自动化检查不能替代这些交互验收。

## 3. 创建发行草稿

合并到 main 并等待 CI 通过后，检查版本与变更日志，再执行：

```sh
git pull --ff-only
version=$(cat VERSION)
git tag -a "v${version}" -m "MenuPocket ${version}"
git push origin "v${version}"
```

标签工作流重新检查、测试、构建 Universal 临时签名应用并打包，创建 GitHub Release **草稿**。带 `-` 的版本自动标记预发行。维护者检查草稿说明和附件后，再在 GitHub 发布；草稿不会自动面向普通用户发布。

附件包含 ZIP、`SHA256SUMS` 和 `build-info.json`。校验：

```sh
shasum -a 256 -c SHA256SUMS
```

同名 Release 已存在时工作流失败，避免静默覆盖发布物。不要移动已经发布的标签；修复应递增版本。

## 4. 签名与公证边界

当前自动构建使用 ad hoc 临时签名，**没有 Apple Developer ID 身份或公证**。ZIP 是开发预览产物，不能宣称下载安装后免授权、免系统提示。SHA-256 用于核对下载完整性，不等同于开发者身份认证。

具备 Apple Developer 证书后，可使用 `--sign developer-id` 在受控环境构建，通过 Apple `notarytool` 提交公证、`stapler` 装订票据，并重新打包和生成校验值。仓库尚未配置这条公证流水线；完成前不要把临时签名草稿描述为正式发行版。

## 5. 故障与回退

构建失败时先看失败步骤和 `swift --version`；版本不匹配应修改源码版本并重新创建尚未公开的标签，或用新版本发布。签名失败不要输出证书密码到日志。

用户回退应用前备份 `layout.json`，确认旧版本能读取配置格式。更新签名或安装位置可能需要重新授权辅助功能。构建元数据记录提交号，便于定位对应源码。
