# MenuPocket 开发与构建

## 1. 准备环境

构建需要 macOS、Swift 6 或更新工具链、Python 3，以及 Git。安装 Xcode Command Line Tools 或带 Swift 6 的 Xcode，确认：

```sh
xcode-select --install
swift --version
python3 --version
```

若已经安装开发工具，不必重复安装。部署目标为 macOS 13，编译所用 SDK 必须支持源码中的新系统接口。CI 使用 macOS 15 runner 自带 Xcode 工具链，并在日志记录版本。

默认本地签名需要 OpenSSL 3。使用 Homebrew 的开发者可运行 `brew install openssl@3`；脚本自动查找标准 Homebrew 路径，也支持 `OPENSSL_BIN=/absolute/path/to/openssl`。无需本地固定身份的构建可选择 `--sign adhoc`。

## 2. 构建和运行

```sh
bash scripts/build.sh
open dist/MenuPocket.app
```

默认构建 release 配置、本机架构，并使用项目固定签名。产物为 `dist/MenuPocket.app` 和记录版本、架构、工具链、提交号的 `dist/build-info.json`。

| 参数 | 可选值 / 默认值 |
| --- | --- |
| `--arch` | `native`（默认）、`arm64`、`x86_64`、`universal` |
| `--configuration` | `release`（默认）、`debug` |
| `--sign` | `local`（默认）、`adhoc`、`developer-id`、`none` |
| `--output` | 输出目录，默认 `dist` |
| `--build-number` | 数字，CI 默认采用运行编号，本地默认 2 |

例如构建隔离的双架构产物：

```sh
bash scripts/build.sh --arch universal --sign adhoc --output dist/preview
bash scripts/package.sh dist/preview
(cd dist/preview && shasum -a 256 -c SHA256SUMS)
```

不要把临时签名产物覆盖到已获辅助功能授权的开发应用路径。重复打包前更换输出目录或移走旧压缩包；脚本拒绝覆盖已有同名归档。

## 3. 签名模式

- `local`：创建 `.local-signing/` 专用钥匙串，复用同一开发身份，减少调试中的重复授权；不是 Apple 公证。保留该目录，不提交或分享其中内容。不会修改系统根信任。
- `adhoc`：无需证书，适合 CI 验证；不提供可验证的开发者身份，重建可能改变授权身份。
- `developer-id`：从已解锁钥匙串读取 `CODESIGN_IDENTITY`，启用 hardened runtime 和时间戳。要求维护者自备有效证书；此选项本身不执行公证。
- `none`：用于调试构建，打包脚本拒绝发布该模式。

```sh
CODESIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' bash scripts/build.sh --arch universal --sign developer-id --output dist/signed
```

不要把证书、密码或开发钥匙串提交到仓库。

## 4. 检查、测试和截图

```sh
make check
make test
make screenshots
make ci
```

`check` 检查版本、文档本地链接、敏感产物误提交和脚本语法。`test` 运行独立 Swift 模型断言，覆盖布局、偏好和配置保护，不要求辅助功能授权。`ci` 执行检查、测试、通用构建和打包。

截图导出器编译实际视图，注入临时配置和演示项目，不读取用户布局，不操作真实菜单栏。输出在 `docs/images/`，人工检查后提交。它需要可用的 macOS 图形会话，不在无界面 CI 中执行。

真实隐藏和点击需要在已授权的桌面会话手动验收，见 [验证记录](../VERIFICATION.md)。

## 5. 目录结构

```text
Sources/MenuPocket/  原生应用
Tests/               独立模型测试
scripts/             检查、构建、签名、打包
tools/              截图导出器（不进入应用包）
docs/                使用、构建、发布教程与图片
.github/workflows/   PR 检查与标签发布
VERSION              唯一发行版本来源
```

## 6. 直接使用 GitHub 构建

无需本机编译：打开仓库 **Actions → CI → Run workflow**，选择 `main` 并运行。需要仓库写权限；其他用户可 Fork 后在自己的仓库开启 Actions 并运行。

等待三个任务全部变绿，在该次运行页面底部 **Artifacts** 下载 `MenuPocket-macOS-universal-提交号`。先解压下载的 artifact，再解压内部的 `MenuPocket-版本-macOS-universal.zip`，得到 `MenuPocket.app`；同目录提供校验文件和构建信息。下载 artifact 通常需要登录 GitHub，文件保留 14 天。

这是临时签名开发预览，未经过 Apple 公证；系统可能拦截下载的应用。遇到系统阻止时，建议使用上文源码本地构建流程，不需要关闭系统安全机制。首次运行仍需自行授予辅助功能权限。
