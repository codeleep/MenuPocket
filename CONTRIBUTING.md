# 参与 MenuPocket

## 1. 开始开发

阅读 [构建教程](docs/BUILDING.md) 和 [实现结构](docs/ARCHITECTURE.md)。从 main 创建分支，修改保持聚焦，并为会改变布局或配置的逻辑补充有效测试。

```sh
make check
make test
bash scripts/build.sh --sign adhoc --output dist/contribution
```

## 2. 提交 Pull Request

说明问题、最终行为、验证方式和未验证范围。UI 变化附演示数据截图；涉及原菜单点击时写明 macOS、CPU、显示器和目标应用版本。不要把编译通过描述为真实图标兼容。

不提交 `.local-signing/`、构建产物、用户配置或未脱敏诊断。更改行为时同步更新教程和变更日志。

## 3. 反馈问题

使用仓库 Issue 模板，提供可复现步骤、预期与实际结果，以及相关版本。权限状态只需文字说明，不必公开整张隐私设置或桌面截图。安全问题见 [安全报告](SECURITY.md)。
