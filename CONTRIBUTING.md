# Contributing to SnapNest

欢迎提交缺陷报告、体验反馈和 Pull Request。

## 开发环境

- macOS 15 或更新版本。
- Swift 6 工具链，可使用 Xcode 或 Command Line Tools。
- 没有第三方运行时或包依赖。

```sh
git clone https://github.com/hdygxsj/SnapNest.git
cd SnapNest
swift build
swift run ShituCoreChecks
swift run Shitu --verify-editor
```

核心检查使用可执行测试目标，不依赖完整 Xcode 的 XCTest。请为坐标、拼接、导出和状态处理等逻辑修改添加有针对性的回归测试。

## 本机运行

先退出已运行的拾图，再执行：

```sh
./scripts/build-app.sh
open dist/拾图.app
```

App Bundle、构建缓存和本地签名材料不提交到 Git。屏幕捕获需要手动授予系统权限，开发版重新构建后可能需要重新授权。

示例编辑器和工具条渲染不需要捕获真实屏幕：

```sh
# 先退出正在运行的拾图
open dist/拾图.app --args --demo-editor
swift run Shitu --render-toolbar "$PWD/.build/toolbar-preview.png"
```

## 提交问题

请注明 macOS 版本、操作步骤、预期和实际结果。请勿上传包含个人信息的屏幕截图、录屏、令牌或签名证书。

## Pull Request

说明改动解决的问题和完成的验证。界面修改请附不含个人信息的示例图片。涉及真实屏幕、系统声音、多显示器或登录项的变更，请区分自动化测试与实机验收结果。

提交的贡献将按本仓库的 MIT License 分发。
