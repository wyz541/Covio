# #710 Windows Workbench 顶部动画

## 验证信息

- 日期：2026-11-09。
- 设备：Maxsun 台式机，Intel Core i5-14600KF。
- 系统：Windows 11 Enterprise `10.0.26200`，x64。
- 显示器：HKC `V2719Q`。
- 主显示器：2560 × 1440。缩放为 125%。
- 页面：Workbench Home。
- 截图：无。本 Issue 只改变窗口位置动画。

## 动画参数

- 展开时长为 250 ms。
- 收起时长为 190 ms。
- 减少动态效果时长为 120 ms。
- 动画使用缓出曲线。
- 动画帧间隔上限为 8 ms。
- 展开从窗口完全位于屏幕上方开始。
- 收起结束于窗口完全位于屏幕上方。

## 原生展开时间线

窗口物理高度为 1100 像素。

测试记录如下：

- `334 ms`：窗口顶部为 `-714`。
- `423 ms`：窗口顶部为 `-242`。
- `522 ms`：窗口顶部为 `-15`。
- `571 ms`：窗口顶部为 `0`。
- 最终窗口可见。

## 原生收起时间线

收起在指针离开 500 ms 后开始。

测试记录如下：

- `557 ms`：窗口顶部为 `-194`。
- `604 ms`：窗口顶部为 `-498`。
- `716 ms`：窗口顶部为 `-927`。
- `838 ms`：窗口顶部为 `-1100`。
- `853 ms`：窗口不可见。

## 视觉结果

- Workbench 从屏幕上方连续向下拉出。
- Workbench 连续向上回收。
- 显示阶段没有单帧闪现。
- 收起阶段没有单帧消失。
- 顶部中央触发继续正常。
- 自动隐藏和再次触发继续正常。

## 自动验证

以下命令通过：

- `cargo test -p covio-platform -p covio-windows --all-targets`
- `cargo clippy -p covio-platform -p covio-windows --all-targets -- -D warnings`
- `cargo build -p covio-windows`
- `scripts/test-windows-rust.sh`
- `scripts/test-rust.sh`

## 验收结果

- 展开动画有连续中间帧。
- 收起动画有连续中间帧。
- 最终位置为 `Top=0`。
- 收起位置为窗口高度以上的完整隐藏位置。
- 减少动态效果使用 120 ms。
