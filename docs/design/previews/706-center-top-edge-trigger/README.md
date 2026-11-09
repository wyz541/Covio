# #706 Windows 顶部中央触发区

## 验证信息

- 日期：2026-11-09。
- 设备：Maxsun 台式机，Intel Core i5-14600KF。
- 系统：Windows 11 Enterprise `10.0.26200`，x64。
- 显示器：HKC `V2719Q`。
- 主显示器：2560 × 1440。缩放为 125%。
- 截图：无。本 Issue 不改变视觉界面。

## 触发区域

- 触发区位于显示器顶部。
- 触发区高度为 2 像素。
- 触发区以显示器水平中心为中点。
- 触发区左右各为显示器宽度的 5%。
- 触发区总宽度为显示器宽度的 10%。
- 主显示器物理触发范围为 `1152..1407`。
- 触发区物理宽度为 256 像素。

## 原生验证

测试使用临时数据目录。测试启用顶部触发。

测试结果如下：

- 鼠标位于左上区域 `x=900, y=0`。等待 1200 ms。窗口不可见。
- 鼠标位于中央区域 `x=1024, y=0`。等待 2500 ms。窗口可见。
- 窗口矩形为 `Left=544, Top=0, Width=960, Height=880`。
- 鼠标离开窗口。等待 1200 ms。窗口不可见。
- 鼠标位于右上区域 `x=1600, y=0`。等待 1200 ms。窗口不可见。
- 测试结束后，鼠标限制已释放。

## 自动验证

以下命令通过：

- `cargo test -p covio-platform -p covio-windows --all-targets`
- `cargo clippy -p covio-platform -p covio-windows --all-targets -- -D warnings`
- `cargo build -p covio-windows`
- `scripts/test-windows-rust.sh`

## 验收结果

- 顶部中央区域显示 Workbench。
- 顶部左侧区域不显示 Workbench。
- 顶部右侧区域不显示 Workbench。
- 自动隐藏继续工作。
- 多显示器偏移逻辑保持不变。
