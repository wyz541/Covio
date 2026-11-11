# iOS SwiftUI 宿主

本文件说明 iOS 首版 vertical slice 的结构、构建方法和运行边界。
真机验收证据由 [#743](https://github.com/wyz541/Covio/issues/743) 记录。

## 1. 范围

当前切片包含以下用户流程。

1. 创建或读取受 Keychain 保护的本机身份。
2. 使用两个二维码完成设备配对。
3. 选择已配对设备和本地文件。
4. 接收端确认文件报价。
5. 前台发送或接收一个文件。
6. 应用进入后台时暂停传输。
7. 应用回到前台时恢复可重连任务。
8. 只读展示设备系统、版本、在线状态和能力。

当前切片不提供后台持续接收。
当前切片不替代 #743 的三平台真机验收。

## 2. 结构

```text
iosApp/
  Covio/
    CovioApp.swift
    AppModel.swift
    CovioBridge.swift
    BridgeModels.swift
    PlatformServices.swift
    SendView.swift
    ReceiveView.swift
    DevicesView.swift
    PairingView.swift
    QRCodeView.swift
  CovioTests/
    CovioBridgeTests.swift
  Covio.xcodeproj/
```

`CovioBridge` 调用 `covio_mobile_*` C ABI。
`AppModel` 只保存显示状态和平台生命周期状态。
Rust 保存身份、配对信任、传输任务、检查点和错误语义。

```text
SwiftUI
  -> covio_mobile_call
  -> covio-ffi
  -> covio-core
  -> covio-platform
```

## 3. 身份与配对

Rust 在第一次启动时生成 Ed25519 设备身份。
`CredentialVault` 使用 Keychain 保存根密钥。
设备私钥不进入 Swift。
设备私钥不进入 C ABI 返回值。

配对使用两个二维码。

1. 发起端显示报价二维码。
2. 响应端扫描报价二维码。
3. 响应端显示响应二维码和六位确认码。
4. 发起端扫描响应二维码。
5. 两端核对同一个六位确认码。
6. 两端分别确认配对。

报价和响应包含名称、公钥、能力、系统名称和系统版本。
签名覆盖上述字段。
确认码来自经过认证的配对 transcript。

## 4. 文件传输

发送端先选择文件。
Rust 计算 BLAKE3 清单并显示文件报价。
接收端接受报价后，Rust 写入同卷暂存文件。
Rust 按 1 MiB 分块接收数据。
Rust 按 8 MiB 窗口控制发送。
接收端为每个持久分块返回检查点。
接收完成后，Rust 校验文件摘要并原子提交。

文件内容只进入数据流。
文件内容不进入 JSON 控制命令。

## 5. 生命周期

应用进入后台时，Swift 调用 `mobile.lifecycle.background`。
Rust 请求活动 worker 停止读取新分块。
Rust 保存最后一个持久检查点。
任务状态显示为 `background_deferred` 或 `paused`。
任务不显示为失败。

应用回到前台时，Swift 调用 `mobile.lifecycle.foreground`。
Rust 重新建立可信连接。
Rust 比较设备身份和清单摘要。
Rust 从持久检查点继续传输。

## 6. 平台 adapter

Swift 使用以下系统入口。

| 能力 | iOS API | 行为 |
| --- | --- | --- |
| 文件选择 | SwiftUI `fileImporter` | 用户选择一个文件 |
| 分享 | `UIActivityViewController` | 分享已完成文件 |
| 通知 | `UNUserNotificationCenter` | 提示新报价和完成事件 |
| 相机 | `AVCaptureSession` | 扫描配对二维码 |
| 生命周期 | SwiftUI `scenePhase` | 暂停和恢复任务 |
| 安全存储 | Rust Keychain adapter | 保护设备身份根密钥 |

首次发送或开始接收时，Covio 请求通知权限。

接收文件保存在应用 `Application Support/Covio/Received`。
发送文件副本保存在应用 `Application Support/Covio/Outbox`。

## 7. 构建

构建环境要求如下。

1. Apple Silicon Mac。
2. Xcode 16 或更新版本。
3. iOS 17 或更新版本的 SDK。
4. Rust 1.91 或更新版本。

构建模拟器目标。

```sh
bash scripts/build-ios-swift.sh
```

构建真机目标。

```sh
IOS_DESTINATION='generic/platform=iOS' bash scripts/build-ios-swift.sh
```

运行模拟器测试。

```sh
bash scripts/test-ios-swift.sh
```

Xcode 构建阶段调用 `scripts/build-ios-rust.sh`。
脚本按目标架构构建 `libcovio_ffi.a`。
脚本把静态库复制到 `BUILT_PRODUCTS_DIR`。
Xcode 从同一目录链接静态库。

## 8. 验证

可移植检查运行以下命令。

```sh
python3 -I scripts/validate-ios-project.py
```

Apple Silicon 检查运行以下命令。

```sh
bash scripts/test-ios-swift.sh
```

本地网络回环传输检查运行以下命令。

```sh
cd rust
cargo test -p covio-ffi loopback_transfer_completes_and_preserves_bytes -- --ignored
```

检查覆盖以下内容。

1. Xcode 工程结构和共享 scheme。
2. Swift `mobile.status` round-trip。
3. C ABI request dispatch。
4. C ABI cancellation。
5. C ABI shutdown。
6. Swift 和 Rust 的 JSON 合同。
7. iroh 本地网络回环传输。

GitHub Actions 不运行 iOS 构建。
iOS 构建和真机验收在本地 Apple Silicon Mac 执行。

## 9. 当前限制

1. 首版只传输单文件。
2. 目录清单由 #739 交付。
3. iOS 不承诺后台持续接收。
4. 远端在线状态来自当前可信会话。
5. 远端最近在线时间来自配对记录。
6. 真机证据尚未写入 #743。

## 10. 关联文档

- [跨平台产品架构](cross-platform-product.md)
- [C ABI 合同](bridge-contract.md)
- [凭据仓库](credential-vault.md)
- [设备配对](device-pairing.md)
- [单文件传输](single-file-transfer.md)
- [共享设计合同](shared-design-contract.md)
