# macOS 跨设备传输入口

macOS 文件页显示一条设备栏。
设备栏提供 Pair、Send 和 Receive 三个入口。
三个入口打开同一个设备面板。

## 页面

| 页面 | 用户操作 | 数据来源 |
| --- | --- | --- |
| Pair | 显示配对二维码，或粘贴另一台设备的二维码内容 | `mobile.pairing.*` |
| Send | 选择文件和已配对设备，然后发送 | `mobile.transfer.send` |
| Receive | 启动接收，确认或拒绝传入文件 | `mobile.transfer.listen`、`mobile.transfer.accept` |
| Devices | 只读查看本机和已配对设备 | `mobile.bootstrap`、`mobile.devices.list` |

## 状态

- 设备栏显示已配对设备数量和监听状态。
- 传输行显示进度、已保存字节、总字节和稳定错误码。
- 传输完成后可以在 Finder 中显示接收文件。
- 网络断开、存储错误、损坏分块、冲突目录和续传点错误显示对应消息。
- 接收目录是 `Application Support/com.wyz.covio/Transfer/Received`。

## 签名和生命周期

macOS 宿主通过 `CovioFFI` 的 `mobile.*` C ABI 访问 Rust core。
设备身份保存在 Keychain 支持的 Rust credential vault。
界面打开时每 500 毫秒刷新传输状态。
界面每 5 秒刷新已配对设备。
macOS 不模拟 iOS 的自后台暂停。

## 验证

- `DeviceTransferModelTests` 覆盖启动、配对、确认和稳定错误码。
- `bash scripts/test-macos-swift.sh` 覆盖 macOS 宿主编译和 XCTest。
- 真实跨设备收发仍由 #743 的三平台矩阵记录。
