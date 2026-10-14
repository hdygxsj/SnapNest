# 轻屿 Pro 上线准备

客户端已接入 StoreKit 2。此文档不代表商品已创建、支付已上线或 App Store 审核已通过。当前产物是本地临时签名测试包。

## 商品

- Bundle ID 保持 `com.shitu.capture`，须确认开发者团队拥有该标识。
- 在 App Store Connect 对应 macOS App 下创建非消耗型内购，Product ID 必须为 `com.shitu.capture.pro.lifetime`。
- 名称「轻屿 Pro」，说明「一次性解锁高清 PNG 与 GIF」。按用户确定的中国区 ¥12 设置价格，核对其他地区价格及可售范围。
- 填写本地化、审核截图与说明，完成付费协议、税务及银行信息。
- 应用显示 `Product.displayPrice`，没有可用商品时禁止购买；代码里的 ¥12 仅为商品未配置时的计划售价。

## 构建与权限

本机目前仅配置 Command Line Tools。需要完整 Xcode、开发者团队签名和 Mac App Store 分发配置。现有 SwiftPM 临时签名打包脚本不是商店上传流程。

提交前需要适配并验证 App Sandbox：屏幕捕获、提醒事项、用户选择保存目录及其持久访问、快捷启动和跨应用选中文字均需逐项确认。当前版本不能仅更换签名后就视为可上架版本。

不需要为了本次单一买断商品搭建支付服务器。客户端只通过 StoreKit 验证后的当前权益和交易更新解锁，不通过本地偏好字段授予 Pro。可在未来按业务需要增加服务器通知与管理。

## 必须完成的真实交易测试

1. Xcode StoreKit 测试：成功、取消、待批准、失败、退款撤销、重复购买、恢复购买。
2. App Store 沙盒：真实商品读取与价格、验证交易、重启恢复、同一 Apple 账户重新安装恢复、离线启动后的已有权益、退款后撤销。
3. Retina 实机：标准 PNG 与 Pro PNG 的像素尺寸、剪贴板、编辑和长截图；GIF 对比 960/10 fps 与 1920/20 fps，并检查小区域不放大。
4. 在有屏幕录制权限的设备验证区域、窗口、多显示器捕捉，以及录制暂停/恢复；当前自动测试不代替这些检查。

现有 `Tests/ProChecks/run.sh` 使用模拟服务覆盖客户端状态转换；`swift run ShituCoreChecks` 验证生成 GIF、帧率与画质选择。两者都不证明真实 Apple 账户交易成功。

参考：[Apple 内购](https://developer.apple.com/in-app-purchase/)、[当前交易权益](https://developer.apple.com/documentation/storekit/transaction/currententitlements)。
