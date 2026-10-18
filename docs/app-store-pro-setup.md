# 轻屿 App Store 上线准备

2026-10-18：已取消付费 Pro，所有功能免费，客户端不再集成 StoreKit 或内购商品。此文件沿用旧路径以保留链接；不再按历史付费方案创建商品。

## 构建与权限

2026-10-15 检查发现本机已安装 `/Applications/Xcode.app`（16.2 / 16C5032a），但默认开发者目录仍为 Command Line Tools。可通过单次命令的 `DEVELOPER_DIR` 使用完整 Xcode，不必修改系统设置。`security find-identity -v -p codesigning` 返回 0 个有效签名身份。仍需开发者团队签名和 Mac App Store 分发配置；现有 SwiftPM 临时签名打包脚本不是商店上传流程。

提交前需要适配并验证 App Sandbox：屏幕捕获、提醒事项、用户选择保存目录及其持久访问、快捷启动和跨应用选中文字均需逐项确认。当前版本不能仅更换签名后就视为可上架版本。

本次代码检查已确认：保存目录只持久化路径，未保存 security-scoped bookmark；文件夹收藏同样需要检查重启后的授权；划词使用 AXUIElement 读取其他应用，苹果将辅助应用的这类 API 列为与沙盒不兼容。商店版应改为系统 Services 接收用户主动发送的选中文字，并保留显式粘贴入口，不能靠提示用户授权就视为解决。参考：[Apple 沙盒兼容性说明](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)。

中文商品资料草稿位于 `docs/app-store/metadata.zh-Hans.json`，尚未提交。仍缺公开隐私政策和支持地址、审核联系方式、版权主体；不得用占位信息提交。当前 App Store Connect 登录页未取得已登录会话，内嵌浏览器也未呈现登录表单，需用户在可正常登录的浏览器完成登录。

## 验证

- 画质偏好与旧设置迁移：`swift run Shitu --verify-quality`。
- 办公功能：`swift run Shitu --verify-office`。
- GIF/PNG 参数与编码：`swift run ShituCoreChecks`。
- 提交前仍需实机确认屏幕录制权限、Retina 捕捉、剪贴板、沙盒兼容性和开发者签名。
