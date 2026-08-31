# Kumo TestFlight 内部测试发布说明

## 目标

使用现有“问命书”Apple Developer Team 发布 Kumo 的 TestFlight Internal Only 构建，供团队内部安装验证；不提交外部 Beta 审核，也不提交 App Store 审核。

## 标识与隔离

- App Store Connect 名称：`Kumo`
- App 内显示名称：`Kumo`
- 内部版 Bundle ID：`com.wenmingshu.kumone.internal`
- 首个内部构建：`0.3.15 (1)`
- 签名方式：Apple Distribution + App Store provisioning profile
- 分发范围：TestFlight Internal Only

内部版不使用上游工程的 `sb.moe.kumone`，避免占用或影响上游作者的 Apple Bundle ID。问命书主 App、Widget、证书配置和线上版本均不修改。

## 上传前要求

- 使用独立 App ID、App Store Connect 应用记录和描述文件。
- `PrivacyInfo.xcprivacy` 声明应用自身 `UserDefaults` 的必要原因 `CA92.1`。
- `ITSAppUsesNonExemptEncryption=false`，应用不包含自研或非豁免加密算法。
- 构建必须为 arm64、Release、`get-task-allow=false`，并完成 Apple Distribution 深度签名。
- 上传时启用 `testFlightInternalTestingOnly`，确保该构建不能转为外部测试或正式发布。

## 本机构建

- 只读检查签名材料：`/Users/ellic/code/zhimingshu/.venv/bin/python Scripts/prepare-testflight-signing.py --status`
- 导出本地签名 IPA：`Scripts/build-testflight.sh`
- 校验归档并上传：`Scripts/build-testflight.sh --upload`
- 内部版在构建命令中覆盖 Team、Bundle ID、版本和显示名，不修改 GitHub 侧载版使用的 `sb.moe.kumone`。

## 验收

- App Store Connect 处理状态为 `VALID`。
- 构建进入 Kumo 自己的内部测试组，不能加入问命书测试组。
- TestFlight 显示版本、构建号和中文测试说明正确。
- 内部测试者可从 TestFlight 安装，且不会覆盖问命书 App。
