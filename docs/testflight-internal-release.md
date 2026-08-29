# Kumone TestFlight 内部测试发布说明

## 目标

使用现有“问命书”Apple Developer Team 发布 Kumone 的 TestFlight Internal Only 构建，供团队内部安装验证；不提交外部 Beta 审核，也不提交 App Store 审核。

## 标识与隔离

- App Store Connect 名称：`Kumone 内部测试`
- App 内显示名称：`Kumone`
- 内部版 Bundle ID：`com.wenmingshu.kumone.internal`
- 版本：`0.3.12`
- 签名方式：Apple Distribution + App Store provisioning profile
- 分发范围：TestFlight Internal Only

内部版不使用上游工程的 `sb.moe.kumone`，避免占用或影响上游作者的 Apple Bundle ID。问命书主 App、Widget、证书配置和线上版本均不修改。

## 上传前要求

- 使用独立 App ID、App Store Connect 应用记录和描述文件。
- `PrivacyInfo.xcprivacy` 声明应用自身 `UserDefaults` 的必要原因 `CA92.1`。
- `ITSAppUsesNonExemptEncryption=false`，应用不包含自研或非豁免加密算法。
- 构建必须为 arm64、Release、`get-task-allow=false`，并完成 Apple Distribution 深度签名。
- 上传时启用 `testFlightInternalTestingOnly`，确保该构建不能转为外部测试或正式发布。

## 验收

- App Store Connect 处理状态为 `VALID`。
- 构建进入 Kumone 自己的内部测试组，不能加入问命书测试组。
- TestFlight 显示版本、构建号和中文测试说明正确。
- 内部测试者可从 TestFlight 安装，且不会覆盖问命书 App。

