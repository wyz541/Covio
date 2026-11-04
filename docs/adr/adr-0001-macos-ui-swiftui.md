# ADR-001：macOS UI 层迁移到 SwiftUI，KMP 作为共享底座

- Status：accepted
- Kind：architecture
- Date：2026-10-12
- Supersedes：none
- Superseded by：ADR-0017（仅截图接管部分）、ADR-0030（仅 KMP shared-foundation 决策）
- Implements：none
- 阶段：M0 到 M6 已结案
- 补充：2026-10-12 对齐共享层边界。结论见实测 26 到 28
- 补充：2026-10-12 补记实测 29 与 30：测试宿主不启动运行时；图标是工程资源
- 补充：2026-10-12 补记实测 31 到 34：Hub 外壳按 macOS 27 版式重做，部署目标提到 26.0；搜索锚点漏挂两处。玻璃的显示效果待真机确认
- 补充：2026-10-12 补记实测 35 到 37：CI 推送后两次失败。冷缓存下 konanc 找不到；测试写死屏幕坐标，只在有刘海的本机上通过。第三次三个作业全绿，378 条测试
- 补充：2026-10-13 补记实测 38 与 39：Escape 的两段行为搬进可测的类型；测试的固定等待换成轮询

## 背景

Covio 当前用 Compose Multiplatform 画 macOS 界面。构建系统是 Amper 0.12.1，不是 Gradle。

`app/src/com/wyz/covio/app/platform/MacShelfNative.kt` 通过反射拿到 AWT `Component.peer`，再用 `objc_msgSend` 发消息。这是全仓库最脆弱的耦合。

Hub 挂帘需要非激活面板、鼠标穿透、全宽工具条。这些能力在 Compose Desktop 上很难做。

计划把 macOS 界面换成 SwiftUI。KMP 保留为共享底座。共享层要产出 framework 供 Xcode 链接。

## 决策

1. macOS 界面用原生 SwiftUI 与 AppKit。
2. 共享领域逻辑放新模块 `kmpDomain`，平台含 `jvm` 与 `macosArm64`。
3. 与操作系统相关的实现按平台分开，由 KMP 统一管理接口。
4. `macosApp` 是独立的 Xcode 工程，不注册进 Amper 的 `project.yaml`。
5. macOS framework 由 `scripts/build-kmp-framework.sh` 调用 `konanc` 产出，不依赖 Amper 的 Xcode 集成。
6. Xcode 工程的源码用 `PBXFileSystemSynchronizedRootGroup` 引用目录。新增 Swift 文件不改 `project.pbxproj`。
7. 平台集成相关的逻辑留在宿主。界面、OS 调用、宿主生命周期不进共享层。判断依据见实测 26 到 28。

## 证据

M0 spike 的执行结果。全部在本机实测。环境是 macOS 27.0.1、Xcode 27.0、Swift 6.4、Apple Silicon。

### 实测 1：`macosArm64` 编译通过

`kmpDomain/module.yaml` 声明 `platforms: [jvm, macosArm64]`。执行 `/bin/sh ./kotlin build`。

```text
✓ Compilation successful for 'kmpDomain' [macosArm64]
Build successful
```

产出 `build/tasks/_kmpDomain_compileMacosArm64Debug/kmpDomain.klib`。

注意产物目录与任务名把平台首字母大写：`compileMacosArm64Debug`，不是 `compilemacosArm64Debug`。

### 实测 2：Amper 不产出 macOS framework

`./kotlin build` 生成的任务里没有 framework 任务。

```text
_kmpDomain_compileMacosArm64Debug
_kmpDomain_compileMacosArm64Release
_kmpDomain_compileMacosArm64TestDebug
_kmpDomain_jarJvm
```

`./kotlin package -f` 的取值只有 `jar | executable-jar | aab | maven-central-bundle`。没有 framework 格式。

`./kotlin show settings -m kmpDomain` 的完整设置树里也没有 native framework 的声明项。

### 实测 3：Amper 的 Xcode 集成不支持 macOS SDK

`kotlin tool xcode-integration` 是 Xcode 脚本阶段调用的隐藏命令。用 macOS 的环境变量执行：

```text
ERROR: The Kotlin Toolchain currently doesn't support building the following configuration: arch=arm64, sdk=macosx
```

Amper 的 Xcode 集成只覆盖 iOS 一族。旁证：

- `amper-project-templates-jvm.jar` 只有 iOS 模板，没有 macOS 模板。
- iOS 模板的 pbxproj 写死 `SDKROOT = iphoneos`。
- 集成命令的 prebuild 步骤引用 `IosPreBuildTask`。

### 实测 4：`product: type: macos/app` 不是 SwiftUI 宿主

Amper 0.12.1 的产品类型全集是：`jvm/app`、`jvm/lib`、`kmp/lib`、`android/app`、`ios/app`、`macos/app`、`linux/app`、`windows/app`、`js/app`。

没有 `swift/app`。`macos/app` 走 Kotlin/Native 链接任务：

```text
ERROR: could not find '/main' function.
ERROR: Task ':macosApp:linkMacosArm64Debug' failed: native compilation failed with 1 error
```

### 实测 5：konanc 产出 macOS framework，含依赖

`scripts/build-kmp-framework.sh` 的实现依据。

`konanc -produce framework` 的位置参数被当作源码，所以不能把 klib 放在位置参数上：

```text
error: source entry is not a Kotlin file: .../kmpDomain.klib
```

只用 `-library` 传入主 klib 会报 `you have not specified any compilation arguments`。

正确的做法是用 `-Xinclude`：

```sh
konanc -produce framework \
  -target macos_arm64 \
  -Xbinary=bundleId=com.wyz.covio.kmpDomain \
  -Xinclude=build/tasks/_kmpDomain_compileMacosArm64Release/kmpDomain.klib \
  -library <serialization-json-macosarm64 klib> \
  -library <serialization-core-macosarm64 klib> \
  -o build/kmp-framework/kmpDomain
```

产出：

```text
kmpDomain.framework/kmpDomain: Mach-O 64-bit dynamically linked shared library arm64
```

framework 的 `Info.plist` 含 `CFBundleSupportedPlatforms = [MacOSX]`。头文件导出正确的 Swift 名：

```objc
__attribute__((swift_name("Probe")))
@interface KmpDomainProbe : KmpDomainBase
- (NSString *)greetName:(NSString *)name __attribute__((swift_name("greet(name:)")));
```

### 实测 6：依赖 klib 的收集方式

konanc 直接调用绕过了 Amper 的依赖解析。不要扫 `.m2.cache`，因为同一 artifact 会有多个版本：

```text
kotlinx-serialization-json-macosarm64/1.7.3/...
kotlinx-serialization-json-macosarm64/1.11.0/...
```

版本必须问 Amper 要：

```sh
/bin/sh ./kotlin show dependencies -m kmpDomain --platform-group=native --scope=compile
```

它给出解析后的图，含 `1.7.3 -> 1.11.0` 这类覆盖关系。脚本从这个输出里抽取 `group:artifact-macosarm64:version`，再映射到 `.m2.cache` 的 Maven 布局路径。

`kotlin-stdlib` 由 konanc 发行版自带，不需要收集。

### 实测 7：Swift 可以实现 Kotlin 导出的 interface 并双向注入

这是 Ports 设计的前提。Kotlin 侧：

```kotlin
interface GreeterPort {
    fun greet(name: String): String
}
```

导出为 Objective-C protocol。Swift 侧实现并传回 Kotlin：

```swift
private final class SwiftGreeter: NSObject, GreeterPort {
    func greet(name: String) -> String { "swift: \(name)" }
}

PortHost().runWith(port: SwiftGreeter(), name: "M0")   // "swift: M0"
PortHost().kotlinPort().greet(name: "M0")              // "kotlin: M0"
```

两个方向都通过。约束是 Swift 实现类必须继承 `NSObject`，因为导出目标是 Objective-C protocol。

### 实测 8：刘海几何可以直接读，不用猜

`NSScreen.auxiliaryTopLeftArea` 与 `auxiliaryTopRightArea` 在 macOS 27 可用，返回非 nil。

本机显示器是内建视网膜屏，`frame` 为 1728×1117：

```text
safeAreaInsets: NSEdgeInsets(top: 32.0, left: 0.0, bottom: 0.0, right: 0.0)
auxiliaryTopLeftArea:  Optional((0.0,   1085.0, 771.5, 32.0))
auxiliaryTopRightArea: Optional((956.5, 1085.0, 771.5, 32.0))
```

读出的结论：顶部条高 32 pt；刘海占 x 从 771.5 到 956.5，宽 185 pt。

M1 的热区与面板定位应该读这两个属性，不要写死数值。

### 实测 9：`isFloatingPanel` 会把 `level` 静默重置

系统菜单栏的窗口层级是 24。`NSWindow.Level.statusBar` 是 25，刚好高于菜单栏。这个选择是对的。

但设置顺序会决定成败：

| 顺序 | 读回的 `level.rawValue` |
| --- | --- |
| 先 `isFloatingPanel = true`，再 `level = .statusBar` | 25 |
| 先 `level = .statusBar`，再 `isFloatingPanel = true` | **3** |
| 只设 `level = .statusBar` | 25 |

`isFloatingPanel = true` 会把 level 重置为 `.floating`（3）。

**M1 必须按这个顺序写。** 否则面板层级会退回 3，与现有 Compose 版的 `FLOATING_WINDOW_LEVEL = 3` 是同一个错误。

### 实测 10：事件权限的现状

测试进程 `AXIsProcessTrusted = false`、`CGPreflightPostEventAccess = false`。

`NSEvent.addGlobalMonitorForEvents` 对 `.mouseMoved` 与 `.keyDown` 都返回了非 nil 的 token。**注册成功不代表有权限**，所以不能用"注册成功"判断权限。

`CGPreflightPostEventAccess = false` 说明 M4 的合成 ⌘V 现在不可用。用户必须授权辅助功能。

### 实测 11：Amper 能在 macosArm64 上跑 Kotlin 测试

这是本轮最重要的发现。计划原先假设 Kotlin 测试只能跑在 JVM 上。

`kmpDomain` 加测试源后执行 `/bin/sh ./kotlin test`：

```text
✓ Compilation successful for 'kmpDomain' [macosArm64 tests]
Started com.wyz.covio.domain.ProbeTest
Passed greetUsesName
Passed platformNameIsNotEmpty
Passed portHostCallsInjectedPort
Passed portHostReturnsKotlinPort
Started com.wyz.covio.domain.PlatformTest
Passed actualIsMacosArm64
```

测试以原生二进制执行。`expect/actual` 在测试源里也按平台正确解析：

- `test@jvm/` 的 `PlatformTest.actualIsJvm` 通过。
- `test@macosArm64/` 的 `PlatformTest.actualIsMacosArm64` 通过。

测试源集用目录后缀，与主源集一致：`test/`、`test@jvm/`、`test@macosArm64/`。测试框架是 `kotlin.test`，Amper 自动提供，不用声明依赖。

`./kotlin test` 的实际规模是 4 个运行块、128 个测试：

| 运行块 | 测试数 |
| --- | --- |
| `kmpDomain` jvm | 5 |
| `kmpDomain` macosArm64 | 5 |
| `core` jvm | 52 |
| `app` jvm | 66 |

两个运行器的输出格式不同，写日志解析时要注意：

- JVM 运行器（JUnit）打 `Started foo()` 与 `[ N tests found ]` 汇总块。
- Kotlin/Native 运行器打 `Started foo`，**不带括号**，也不打 `[ N tests found ]` 汇总块。

因此按 `tests found` 统计会漏掉 native 那一块。

### 实测 12：`EngineTest` 可以直接跑在 native 上

`core/test/com/wyz/covio/EngineTest.kt` 是 573 行，是计划指定的行为基线。

统计它的 JVM 专用 API 引用（`java.*`、`Thread.`、`System.`、`Files.`、`Path`、`UUID`）结果是 **0**。它只用 `kotlin.test` 的断言与手写 fake。

同一统计下其余测试文件：

| 文件 | 行数 | JVM 专用引用 |
| --- | --- | --- |
| `EngineTest.kt` | 573 | 0 |
| `SmokeTest.kt` | 11 | 0 |
| `PmsetWakeLogParserTest.kt` | 92 | 3 |
| `ShelfLogicTest.kt` | 120 | 10 |
| `VersionAndConfigTest.kt` | 118 | 13 |
| `ShelfStoreTest.kt` | 77 | 15 |

这意味着 M2 不需要把 `EngineTest` 的断言在 XCTest 里重建。把 `Engine` 与它的依赖移进 `kmpDomain` common 之后，这 573 行断言可以原样运行在 macosArm64 上。

`Engine.kt` 本身仍然要改。它用了约 30 处 `synchronized`、`Thread.sleep`、`AtomicBoolean`，这些在 Kotlin/Native 不存在。改造办法见计划的 M2 段。

### 实测 13：热区用 `NSTrackingArea` 就不需要全局监听

这条结掉实测 10 留下的问题。

M1 的热区不用 `NSEvent.addGlobalMonitorForEvents`。做法是每块屏幕一个 `HotZonePanel`，面板的 `contentView` 装 `NSTrackingArea`：

```swift
let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
```

`.activeAlways` 与前台应用无关，`mouseEntered`/`mouseExited` 直接送到面板自己的 `NSView`。

实测环境 `AXIsProcessTrusted = false`，热区照常进出。所以"全局监听是否免权限"这个问题不再影响本方案。

**由此产生的两条设计约束：**

1. `NSTrackingArea` 的 `mouseEntered` 只在下一次鼠标移动时送达。面板刚出现时指针可能已经在面板里。所以 `presentHub()` 在 `orderFrontRegardless()` 之后主动查一次真实指针位置，不在面板里就立刻合成一次 `pointerExitedHub`。否则 Hub 会卡在展开态。
2. Hub 可见时热区面板必须先 `orderOut`。否则 Hub 盖住热区会触发一次假的 `mouseExited`，把刚展开的 Hub 关掉。互斥用面板可见性做，不用 `ignoresMouseEvents`。

### 实测 14：全屏 Space 用 `visibleFrame` 判定，免权限

M0 设想的办法是 `CGSCopyManagedDisplaySpaces` 判 `type == 4`。M1 改用更简单的规则：

```swift
var isMenuBarVisible: Bool { visibleFrame.maxY < frame.maxY }
```

菜单栏在全屏 Space 里自动隐藏。菜单栏一隐藏，`visibleFrame` 就长到顶，两个值相等。这条不需要任何私有 API，也不需要权限。

`ScreenGeometry` 用 `isMenuBarVisible` 决定热区是否显示。切换 Space 时 `NSWorkspace.activeSpaceDidChangeNotification` 触发重算。

### 实测 15：菜单栏区域高度有两个值，差 1 pt

本机内建屏 `frame` 高 1117：

```text
safeAreaInsets.top            = 32.0
frame.maxY - visibleFrame.maxY = 33.0   (1117 - 1084)
```

32 是刘海与圆角的安全区，33 是菜单栏占的实际高度。两者不相等。

M1 的用法：

- 展开矩形的高度用 `safeAreaInsets.top` 加上内容高度，因为卡片要从刘海下沿开始画。
- 菜单栏可见性用 `visibleFrame.maxY < frame.maxY`，因为它比的是"有没有让位"。

不要把这两个值互相替换。

### 实测 16：宿主 XCTest 包加同步目录组的组合

M1 要给 AppKit 类型写单元测试，需要 `@testable import Covio`。做法是把这个测试 target 改成宿主测试包：

```text
TEST_HOST     = $(BUILT_PRODUCTS_DIR)/Covio.app/Contents/MacOS/Covio
BUNDLE_LOADER = $(TEST_HOST)
```

再加一个 `PBXTargetDependency` 指向 app target，测试才会先构建 app。

两项代价：

- 测试跑在真实的 app 进程里。`AppDelegate` 已经把 shell 启动了，所以测试进程里真实存在热区与 Hub 面板。`NotchShellControllerTests.testHostApplicationRunsTheShell` 正是利用这一点验证装配。
- 测试期间面板会真的出现在屏幕上。控制器把指针位置做成可注入的闭包，测试不移动真实鼠标。

配合决策 6 的同步目录组，M1 新增 20 个 Swift 文件没有改过一次 `project.pbxproj`。

### 实测 17：`flock` 按打开的文件描述算

`flock` 的互斥单位是 open file description，不是进程。同一进程里对同一路径调用两次 `open()`，两次 `flock(LOCK_EX | LOCK_NB)` 会互相排斥。

所以单实例锁可以在单元测试里验证，不必真的启动第二个进程。`AppPathsTests.testLockIsExclusiveAcrossDescriptors` 就靠这条。

顺带修掉一个缺陷：`SingleInstanceLock.acquire()` 原先调用 `AppPaths.ensureSupportDirectory()` 建目录，而不是建锁文件自己的父目录。传入自定义路径时 `open()` 报 ENOENT。现改为 `url.deletingLastPathComponent()`。默认路径的父目录就是应用数据目录，行为不变。

### 实测 18：Kotlin 的默认参数不导出到 Swift

`AppConfig` 有 21 个字段。Swift 侧构造它必须写全 21 个参数。`Engine` 也是这样。

两条对策：

- 产品代码只有一处需要默认值：清除配置。`ConfigStore.companion` 因此加了 `defaults()`，内部调 `AppConfig()`。
- 测试要构造变体。`AppConfigs.make(from:)` 从一份基线出发改字段，其余字段用 `doCopy` 原样带回。基线不抄默认值，而是让 `ConfigStore` 在一个空目录里 `load()`，取 Kotlin 自己算出的结果。

抄默认值会漂移。漂移的默认值让两版写出不同的 `config.json`。

### 实测 19：Kotlin 枚举导出成类

Swift 里 `LidState.OPEN` 写成 `.open`。导出时名字转小写。

导出结果是类，不是 Swift 枚举。所以 Swift 的 `switch` 覆盖不了全部取值，必须写 `default:`。`default` 分支会掩盖 Kotlin 侧新增的取值，因此每个 `default` 旁边都注明原因。

受影响的枚举有 `LidState`、`PowerState`、`HelperStatus`、`SleepEvent`、`WakeKind`。

### 实测 20：可空的基本类型装箱

`Int?` 与 `Long?` 到 Swift 变成 `KotlinInt` 与 `KotlinLong`。读数用 `.int32Value` 与 `.int64Value`。构造用 `KotlinInt(int:)` 与 `KotlinLong(longLong:)`。

不可空的 `Int32` 与 `Int64` 直接映射，不装箱。

`Set<Int>` 导出成 `Set<KotlinInt>`，每个元素单独解箱。

### 实测 21：`sun_path` 只有 104 字节

Unix socket 的路径上限是 104 字节。`NSTemporaryDirectory()` 展开成 `/var/folders/…/T/`，本身约占 50 字节。再加一层目录名与 UUID 就超限。

超限时 `bind()` 报 ENAMETOOLONG。`HelperStatusTests` 一开始四条全红，报的是路径过长。

对策：socket 放在 `/tmp/covio-hs-<8 位十六进制>.sock`。测试自己建的目录仍然放在 `NSTemporaryDirectory()`。拆除时两处都删。

### 实测 22：Swift 6 严格并发下的三个逃生口

工程设了 `SWIFT_VERSION = 6.0`。调用 Kotlin 代码时有三处绕不过去：

1. 锁保护的可变状态标 `@unchecked Sendable`。`FakeHelper` 与 `NotificationGate` 用它。安全依据是内部的锁，编译器看不见。
2. 不可变的 Kotlin 单例标 `nonisolated(unsafe) static let`。`AppConfigs.defaults` 用它。Kotlin 的 data class 字段全只读。
3. 跨线程传 Kotlin 对象要先装箱。`KotlinBox<Value>: @unchecked Sendable` 把不可变的 Kotlin 值转成可发送类型。`UpdateInfo?` 与 `AppState` 用它。

计时器回调与通知回调用 `MainActor.assumeIsolated`。这些回调由主运行循环发出，本来就在主线程。

### 实测 23：设计合同改成生成，不手抄

界面要用的文案是 194 条。令牌 69 枚，其中颜色 46 枚、尺寸 23 枚。手抄进 Swift 一定漂移。

`scripts/generate-contract-constants.py` 从 `docs/covio-design-contract.json` 生成 `ContractCopy.swift` 与 `ContractTokens.swift`。`token/art/*` 的 75 枚插图装饰色不导出，界面不该直接用。

生成的条目带自己的合同键。`ContractConstantsTests` 遍历它们，与合同逐条比对。所以改了合同而忘了重跑脚本时测试会失败。

`--check` 模式不写文件，只报告差异并返回 1。`scripts/test-macos-swift.sh` 先跑它，漂移在编译前就被拦住。

### 实测 24：`build-kmp-framework.sh` 必须用 bash 调用

脚本用了进程替换 `<(...)`。`/bin/sh` 在 macOS 是 bash 的 POSIX 模式，它不支持进程替换。用 `sh scripts/build-kmp-framework.sh` 会报语法错误。用 `bash` 调用。

### 实测 25：helper 合同放在 `kmpDomain`

SwiftUI 版要判 helper 的版本是否过期，Compose 版也要判。两版必须用同一份协议。

合同定义在 `kmpDomain/src/com/wyz/covio/core/HelperContract.kt`。Swift 通过 framework 读它，不另抄一份。

### 实测 26：状态机与本地指纹留在宿主

`HubStateMachine` 管 macOS 面板的生命周期。驱动它的是 `NotchShellController` 的 `NSTrackingArea` 回调。

`ClipboardPayload.swift` 的 FNV-1a 指纹给本地缓存文件命名。

两者都不进共享层。理由是两条。

第一，没有跨端消费者。Android 与 Windows 不用这两份状态。

第二，搬 `HubStateMachine` 会丢掉编译期检查。Kotlin 枚举导出成类（见实测 19），Swift 的 `switch` 必须加 `default` 分支。以后新增状态会被 `default` 默默吃掉。

搬指纹函数还要转换数据。Swift 的 `Data` 要逐字节变成 `KotlinByteArray`。收益不抵成本。

等剪贴板图片真的跨设备同步时，再重新判断。

### 实测 27：helper 协议用一份 Kotlin 实现

两侧不再各写一份协议。Compose 版与 SwiftUI 版都调 `kmpDomain` 的 `HelperWire`。

不生成代码。生成器要维护模板与两套目标语言，长期成本高于这一次迁移。

导出形状如下：

- `HelperWire` 是 Kotlin `object`，Swift 侧读作 `HelperWire.shared`。
- 请求与回复复用 `Models.kt` 的 `HelperRequest` 与 `HelperReply`。它们是 `@Serializable` 数据类，两侧同一份。
- 构造回复要用共享层的 `success(requestId:result:)`。**`result` 必须显式传**：Kotlin 的默认参数值不导出（见实测 18）。
- 装 helper 的脚本由 `HelperInstallScript` 给出。plist 里的守护进程标签读 `HELPER_LAUNCH_DAEMON_LABEL`，修掉了 Kotlin 侧写死字面量的问题。

编解码有两处行为变化。两处都不破坏线上兼容。

1. **空 `payload` 被省略。** Kotlin 的 `Json` 用 `encodeDefaults = false`，字段为默认值时不出现在字节里。Swift 版以前发 `"payload":{}`。两侧解码器都容忍两种形状，0.4.2 的 helper 照常应答。
2. **带引号的布尔值解得出来。** `{"version":"1","requestId":"r","ok":"true"}` 解出 `ok = true`。kotlinx-serialization 宽松收下这种写法。0.4.2 从没发过这种形状，所以收下它不会放行任何真实的坏包。

两个 `HelperClient`（JVM 用 NIO，Swift 用 POSIX 套接字）与两个 `HelperServer`（JNA 与 POSIX）保留重复。套接字是 OS 调用，归宿主。

共享语料 `kmpDomain/test/fixtures/helper-wire-vectors.json` 是漂移的关断点。Kotlin 侧 `HelperWireVectorTest` 读它，Swift 侧 `HelperWireParityTests` 用 `#filePath` 读同一份文件，经 framework 断言同样的结果。这同时是导出冒烟测试。

### 实测 28：有状态规则搬进共享层后的接线

三项有状态规则搬进 `kmpDomain`。搬运本身不难，接缝是成本所在。

1. `ShelfPresencePolicy`：晾衣线的显示与隐藏时序。
2. `ShelfMoveCheck`：移动完成后的检查节奏。
3. `ScreenshotTakeover`：截图接管的开关与快照还原。

接缝上有四条约束。

**一，输入输出不用枚举。** Kotlin 枚举导出成类（见实测 19），Swift 侧的 `switch` 会被迫加 `default`。`ShelfPresencePolicy` 的输入用布尔值，决策输出用 `shouldShow` 与 `shouldHide` 两个布尔值。

**二，不返回基本类型的集合。** `ShelfMoveCheck` 用 `ShelfMoveCheckPlan` 值对象给出节奏。返回 `List<Double>` 会导出成 `[KotlinDouble]`（见实测 20）。

**三，可空 `Double` 在两侧都要装箱。** `ShelfPresenceInput` 的 `menuBarCandidateAt` 与 `exitCandidateAt` 从 Swift 传要包成 `KotlinDouble`，读回来要取 `.doubleValue`。

**四，接管与晾衣线共用同一个 `ShelfStore` 实例。** 两个实例写同一个 `shelf.json` 会互相覆盖。`ShelfStore` 内部因此加了 `EngineLock`：接管在后台线程上开关，晾衣线在主线程上落盘。

**新增的导出约束：** Kotlin 导出的类不是 `Sendable`。它被 `@MainActor` 类型持有之后，`Task.detached` 捕获它会过不了 Swift 6 的检查。

办法是加一层 Swift 门面，标 `@unchecked Sendable`。门面本身没有可变状态，共享层内部用可重入锁保护开关状态。这与实测 22 的三个逃生口同类。

系统截图偏好是 OS 调用，所以共享层只定义端口 `ScreenshotPreferencePort`，Swift 侧实现它（继承 `NSObject`，见实测 7）。

### 实测 29：测试宿主不能启动运行时

XCTest 把测试包注进被测应用进程（见实测 16），`applicationDidFinishLaunching` 会照跑一遍。启动路径原先无条件做两件事，所以每跑一次 Swift 套件就动一次用户机器：

1. `AppRuntime.start()` 打开真实的截图接管，改写 `com.apple.screencapture` 的三个键。
2. 同一条路径写真实的 `shelf.json`。实测一次运行把它从 73 字节改成 277 字节，`preferenceSnapshot` 从 null 变成当时的真实偏好。

判据放在 `LaunchEnvironment.isRunningTests()`：XCTest 注入配置时设的环境变量 `XCTestConfigurationFilePath`，或者进程里已经加载了 `XCTestCase` 类。scheme 的 TestAction 不设环境变量，所以第二条不能省。

命中时只跳过单实例仲裁与 `runtime.start()`。界面装配照旧，所以 `testHostApplicationRunsTheShell` 仍然验证得到热区与 Hub 面板。单实例仲裁也要跳过：真实应用在跑时它会失败，那会把整个测试套件终止掉。

验证办法有两条。跑 `scripts/test-macos-swift.sh` 前后比对 `shelf.json` 的 sha256 与 `defaults read com.apple.screencapture`，两者不变。旁证是应用日志里不再出现 `Covio 0.5.0 starting`。

顺带修掉一条不稳定的用例。`ShelfRuntimeTests.testTemporarilyShownThenAutoHidden` 原先靠一次主队列跳转断言 0 秒计时器已经落地。计时器落在哪一轮运行循环取决于主队列上还排着谁，所以它偶尔失败。改成转运行循环等结果。

### 实测 30：图标是工程资源，不是打包步骤

原先只有 `scripts/package-macos-swift.sh` 往包里放图标。Xcode 直接构建出的 `Covio.app` 既没有 `Contents/Resources`，也没有 `CFBundleIconFile`，所以它显示系统的占位图标。

后果不只在开发时难看。macOS 27 的「设备控制和数据访问」这类隐私面板按应用路径取图标。测试宿主跑的是 Xcode 构建的 `Covio.app`，那一行的图标就是占位图。

改法是把 `Covio.icns` 放进 `macosApp/src/`。同步目录组按文件类型归类，非源码文件自动进 Resources，所以没有改 `project.pbxproj`。`Info.plist` 里加 `CFBundleIconFile`。打包脚本从「注入图标」改成「断言图标在包里」。

改完要 `touch` 一次 bundle。图标服务会缓存「这个 bundle 没有图标」这个结论，缓存按 bundle 的修改时间作废。

### 实测 31：部署目标提到 26.0 后 Liquid Glass 才编得过

Hub 的外壳改用 Liquid Glass。三个 API 都需要 macOS 26 以上：`glassEffect(_:in:)`、`Glass.regular.interactive()`、`GlassEffectContainer(spacing:)`。

部署目标原来是 `14.0`。这三个 API 的可用版本都是 macOS 26.0，所以在写玻璃代码之前先把 `MACOSX_DEPLOYMENT_TARGET` 改成 `26.0`：`project.pbxproj` 两处，一处 Debug 一处 Release。

改完之后这三个调用不加 `#available` 判断就能编译通过。**编译通过只证明 SDK 里有这些符号。玻璃在无边框透明面板里的显示效果没有验证。** 见未决事项。

同一个改动带出一个 Swift 6 的语言约束。`GlassSurfaceMode.current` 是 `static var`，一开始写成：

```swift
static var current: GlassSurfaceMode = .glass
```

报错是 `static property 'current' is not concurrency-safe because it is nonisolated global shared mutable state`。改成 `@MainActor static var` 之后通过。修饰 `glassSurface(...)` 的 `@MainActor` 是为这个默认参数加的。

**结论：** 部署目标 26.0 是 Liquid Glass 的前提。CI 的 Swift 作业必须跑在 macOS 26 上，否则测试二进制启动不了。

### 实测 32：竖向导航栏复用 `component/tab-bar`，组件数保持 22

新版式把六个页签从横向栏搬到竖向导航栏。若按新尺寸新增一条合同组件，`metadata.counts.componentSets` 就从 22 变成 23。

没有新增。做法是让 `component/tab-bar` 这条记录同时承担两个版式：

- `nativeSize` 从 `960×52` 改成 `200×370`。两个数都是 Hub 的实际几何值，来源是 `HubMetrics.navRailWidth` 与 `HubMetrics.navRailHeight`。
- `swiftMapping.target` 从 `HubTabBar` 改成 `HubNavRail`。
- `platformMapping["platform/component/tab-bar"].swiftRuntimeTarget` 同步改。这两处必须相等，`scripts/validate-contract.py` 规则 2 会核对。

Figma 侧的组件 `121:12394` 仍是旧横向尺寸。这条偏差记进 `metadata.knownDifferences`，状态 `accepted-native-layout-change`。

`component/page-title` 走同一条路。原来的 `MacPageTitle` 是页内标题，现在标题住在顶部胶囊里，映射目标改成 `HubCapsuleTitle`，`nativeSize` 改成 `420×40`。

顶部胶囊这一层没有合同组件。`component/toolbar` 那条已经被截图工具的 `ShelfPanelContent` 占了，不能改映射。胶囊只沿用了它的高度 40 点，这个数抄进 `HubMetrics.toolbarCapsuleHeight`，注释里写明来源。

**结论：** 外壳改动可以不改组件总数。尺寸与映射目标可以改，改一处就要同步改两处。没有合同组件的视图，尺寸来源要写在代码注释里。

### 实测 33：旧的高度加法漏算，按钮行被裁

`HubMetrics` 原来的两个页内容高度是各自单独算的常数。这两个常数各少算了页面上真实存在的最后一行，每个少约 52 点。

后果是截图页与剪贴板页的卡片高度不够。卡片在 `HubView` 里是 `.clipped()` 的，所以底部那行按钮被裁掉，且没有运行时报错。

改法是让高度可加：

```swift
interiorHeight(for:) = max(navRailHeight,
                           toolbarCapsuleHeight + pageGap + pageContentHeight(for:))
contentHeight(for:)   = interiorHeight + cardPadding * 2
```

`max` 取两列的高者。导航栏高 370 点，所以在占位页与设置页上它都是下限。测试按段核对，逐项断言每页内容高度等于它的组成部分之和，另断言 `interiorHeight(for:)` 不小于导航栏高度，也不小于胶囊加间距加页内容。

**结论：** 常数相加的高度要用一个函数表达，且逐段测。截图比对看不出被裁掉的按钮行。

### 实测 34：目录表里的锚点漏挂两处，搜索跳转静默失效

搜索的跳转靠 `ScrollViewReader.scrollTo(rowID)`。目标不存在时这个方法什么都不做，也不报错。所以「搜得到，点了没反应」不会有任何提示。

`SettingsCatalog` 有 25 条。其中两条没有挂锚点：

| 目录项 | 锚点 | 位置 |
| --- | --- | --- |
| 容量阈值 | `SettingsRowID.batteryCapacity` | 电池页 |
| 剩余时间阈值 | `SettingsRowID.batteryTime` | 电池页 |

两个 `NumberRow` 忘了加 `.settingsRowAnchor(_:)`。

**原有的测试抓不到。** `SettingsCatalogTests` 只核对常量与目录表里的字符串是否一致，没有任何断言看视图挂没挂。

改法是补上两处锚点，再加一个套件 `SettingsRowAnchorCoverageTests`。它扫 `macosApp/src` 下的源码文本：把 `enum SettingsRowID` 里声明的常量名，与所有 `.settingsRowAnchor(SettingsRowID.x)` 里的 `x` 对比，缺一个就失败。README 的 `CopySingleSourceTests` 用的是同一套「读源码文本」的办法，所以不违反「测试不构建视图」这条。

**自证：** 故意删掉电池页的 `batteryCapacity` 锚点后，测试失败并报出这一条；补回后通过。

**结论：** 跳转类功能要有一条「目标真的存在」的静态断言。漏挂锚点的缺陷在界面上是无声的。

### 实测 35：konanc 的发现必须排在 Amper 解压之后

首次推送后 `macOS SwiftUI` 作业的 `Build` 步失败。日志：

```
Cannot find konanc. Looked under .../extract.cache and ~/.konan.
Command PhaseScriptExecution failed with a nonzero exit code
```

运行器是刚分配的机器，`~/Library/Caches/JetBrains/Kotlin` 是空的。`konanc` 由 Amper 下载并解压，而 `scripts/build-kmp-framework.sh` 原来先找 `konanc`、再调 Amper 编译。冷缓存下第一步必然失败。本机跑得通，是因为本机早就跑过 `./kotlin build`，缓存是热的。

同一个提交里 `Kotlin` 作业在同一批运行器上跑 `/bin/sh ./kotlin build` 成功，日志里有 `Downloading kotlin-native-prebuilt-2.4.10-macos-aarch64.tar.gz`。所以 Amper 会自己下载工具链，缺的只是顺序。

**改法：** 脚本里把 Amper 编译任务排到工具链发现之前。同一个任务既产出 klib，也把 `konanc` 与 Amper 自带的 JRE 放进共享缓存。

**结论：** 依赖外部工具链的脚本要显式处理冷缓存。本机跑通不构成证据，因为本机的缓存是热的。

### 实测 36：测试写死屏幕坐标，在有刘海的本机上才通过

`konanc` 修好后，`Test` 步失败 11 条，全部在 `NotchShellControllerTests`。两个根因：

| 断言 | 本机 | 运行器 |
| --- | --- | --- |
| `hubPanelFrame?.width` 等于 `HubMetrics.cardWidth` | 960 | 944 |
| 指针固定在「屏幕顶部中央」，注释称「一定落在面板矩形内」 | 面板贴屏幕顶边，成立 | 面板挂菜单栏下方，指针在面板之外 |

运行器屏幕宽 1024 点。`hubWidth(screenWidth:)` 取「卡片宽度 960」与「屏幕宽度减 80」的较小者，得到 944。运行器屏幕也没有刘海，`panelTop` 是 `visibleFrame.maxY` 而不是 `frame.maxY`。于是 `show()` 之后状态机立刻自查指针，判定在面板外，走 EXIT 而不是 HOVER。

**测试写死的两处坐标都只在「有刘海且够宽的屏幕」上成立。** 本机正是这种屏幕，所以 375 条测试在本机全绿。

**改法：** 指针位置与宽度期望都从 `ScreenGeometry(screen:).expandedRect` 推导。`ScreenGeometryTests` 补三条用例，把运行器的屏幕形状（1024 × 768，无刘海）钉下来，其中一条直接断言「屏幕顶部中央在非刘海面板之外」。

**结论：** 断言可以依赖一块屏幕的几何，但不能依赖本机那一块。期望值要从实现用的同一个函数推导。

### 实测 37：三个作业在 CI 上全绿

提交 `5254d0a` 的运行号 `38269856878`：`Kotlin`、`Contract and scripts`、`macOS SwiftUI` 三个作业都是 success。Swift 作业在 `macos-26` 上执行 378 条测试，0 失败。构建阶段从冷缓存开始，Amper 自取工具链。

`macos-26` 标签可用，部署目标 26.0 的测试二进制能在运行器上启动。

**结论：** CI 的 Swift 作业可用了。冷缓存的耗时包含 Kotlin/Native 工具链下载，整个作业约 2 分钟。

### 实测 38：Escape 的两段行为有了测试，但没在真机上按过

原来的规则只写在 `NotchShellController` 的一个闭包里：查询非空就清查询，查询为空就收起面板。闭包在 `makeHubPanel()` 里，测试拿不到，所以这条规则只有真机能验。

改法是把决策搬到 `HubChromeModel.handleEscape()`，返回值表示这一步是否处理完：

```swift
func handleEscape() -> Bool {
    guard !searchText.isEmpty else { return false }
    clearSearch()
    return true
}
```

控制器改成 `if !self.chrome.handleEscape() { self.requestCollapse() }`。这样两段行为可以逐条断言，不必构建视图。

新增 `HubChromeModelTests` 六条，覆盖三段决策、跳转改状态、跳转保留查询、切分节不动搜索。`ShellPanelTests` 补两条：Escape 的 `keyDown` 走 `onCancel`，别的按键不走。键盘事件用 `NSEvent.keyEvent(with:)` 造，进程内直接调 `keyDown`，不往系统投递事件。

**没验到的部分：** 面板是 `.nonactivatingPanel`，窗口服务器肯不肯把键盘给一个不激活的面板，只有在真机上按一次才知道。`canBecomeKey` 为真只是必要条件。

**结论：** 规则从闭包里搬进可测的类型，就能从「只能真机验」变成「决策有测试、接线有测试」。剩下的那一段要在真机上确认。

### 实测 39：测试的固定等待换成轮询

`NotchShellControllerTests` 原来用「等 0.45 秒再看状态」的办法等动画结束。等待窗口是 `动画时长 + 0.2 秒`，机器被别的编译占满时不够，报出 `Asynchronous wait failed: Exceeded timeout of 2.45 seconds`。本机误报过三次，其中一次发生在并行工作流编译 Kotlin/Native 的时候。

**改法：** 换成轮询。每 20 毫秒查一次条件，上限 3 秒。条件一直不成立时照样失败，所以卡住不会被放过。

改完之后同一个套件在同样的负载下全绿，其中一条用例实际等了 2.8 秒。

**结论：** 等的是「状态变成什么」，不是「过了多久」。用固定时长等异步状态，机器一慢就误报。

### 实测 40：指针切换页签，进入即切，切换后冷却 0.25 秒

工作台顶栏原来只按点选换页签。本次加了第二条入口：指针进入首页入口或某个工作区页签，就切过去。

不做停留延迟。指针进入就切，换完之后 0.25 秒内不再响应指针。停留与冷却都是防误触的办法，取舍不同：停留让快速穿过不切，但每次都要等；冷却让进入立刻响应，代价是扫过顶栏时会先切到第一条碰到的页签。用户选定后者。

冷却期间指针停在别的页签上，那一次不丢。冷却走完就切过去。指针中途离开才取消。少了这条，指针停在某个页签上、冷却也已经走完，界面会卡在旧页签上。

**判定放在哪。** 第一版把判定放进 `HubChromeModel`，模型只发布一个计数，视图收到后再调 `select`。顶栏改版时这条链路暴露了问题：视图要把目标翻译成一次点选，而点选在顶栏上分成首页与工作区两条路。这段翻译写在视图里，换一次外壳就要重写一次。改成把判定放进 `WorkbenchModel`，模型直接调 `select(_:)`，视图只转达指针事件。这是实测 38 的同一条教训。

**复用哪条路。** `select(_:)` 落到已有的 `select(paneID:)`，所以三条规则自动生效，不必写两遍：编辑模式里不换页；换页时面板高度重排；已选中的页签不重复切换。冷却是 `destination` 的 `didSet` 里记的时刻，点选、指针切换、页面按钮都从这一处起算。

**真机验收。** 用 `CGEvent` 投递指针，按顶栏选中态蓝色胶囊的横向范围判断选中的是哪一条。

| 步骤 | 读到 | 期望 | 结果 |
| --- | --- | --- | --- |
| 进入页签立刻切换 | 文件 | 文件 | 通过，0.27 秒 |
| 冷却里进入别的页签不切 | 剪贴板 | 剪贴板 | 通过 |
| 冷却走完自己切过去 | 设备 | 设备 | 通过 |
| 停在已选中的页签上 | 设备 | 设备 | 通过 |
| 停在搜索框上 | 设备 | 设备 | 通过 |
| 停在动作按钮上 | 设备 | 设备 | 通过 |
| 进入首页入口立刻回首页 | 首页 | 首页 | 通过，0.33 秒 |
| 编辑模式里进入现在 | 首页 | 首页 | 通过 |
| 点选压过排着的那一次 | 截图 | 截图 | 通过 |
| 冷却里收起面板 | 文件 | 文件 | 通过 |

冷却窗口只有 0.25 秒，比一次读数还短。所以「冷却里被挡住」不靠中途截图：进入第二个页签，0.14 秒就离开，再看终点仍是第一个页签。冷却失效时，进入那一刻就切了，终点会是第二个页签。

十条全过。「减弱动态效果」检查过：开关打开时冷却照旧。冷却是一次 `Task.sleep`，不查这个开关；改时长不改变这条路径。

0.27 秒不是切换耗时。`readBar` 每次要起一个 `screencapture`，读一次一百毫秒上下，那是有轮询粒度的上限，不是延迟。

**验收脚本的坑。** 脚本原本把指针停在内容区当「离开顶栏」。实测那样停 0.9 到 1.4 秒后，面板会自己收起。改用顶栏里搜索框与第一条页签之间的空档停靠后稳定。这一点只用合成事件复现过，真实鼠标下是同样表现还是投递方式的假象，还没有确认。

**拖拽不会误切。** 按住左键拖到「截图」页签上停 1.4 秒，选中态停在首页。`.onHover` 建在 `NSTrackingArea` 上，拖拽会话接管事件流期间不触发。所以不必加「有鼠标键按下就不上报」的守卫。这一条是在停留版本上测的，指针通路的接线没变。

**顺带发现：** `HubMotion.tabSwitch` 没有被任何界面代码引用，只有定义与合同比对测试。设计合同要求页签切换 160 毫秒横向滑动加淡入。顶栏的滑块用 `matchedGeometryEffect`，但整条链路没有动画事务，实际是跳变。这是本次之前就有的偏差，记在 #128。

**结论：** 「该不该切」的判断要和「怎么切」住在同一个类型里。视图只该知道指针在哪一项上。这样换一次外壳，判定这一层不用动。

## 后果

### 正面

- KMP 共享层的意图保留。`kmpDomain` 仍然编 `macosArm64`，仍然产出可供 Swift 调用的 framework。
- **Kotlin 测试跑在 macosArm64 上。** 共享逻辑的行为基线用 `./kotlin test` 验证，不用在 XCTest 里重建。这削减了 M2 的大部分工作量。
- macOS framework 的产出链路完全由本仓库的脚本控制。不依赖 Amper 的未文档化行为。
- `macosApp` 是纯 Xcode 工程。SwiftUI 侧不再受 Amper 产品类型限制。
- Swift 与 Kotlin 的互操作在 M0 就验证了。Ports 用 Swift 实现没有阻碍。
- Xcode 工程用同步目录组，M1 到 M4 新增 Swift 文件不改 pbxproj。R6 的合并冲突风险因此下降。
- **M1 的壳不依赖任何系统权限。** 热区、全屏 Space 判定、全局快捷键（Carbon）都在 `AXIsProcessTrusted = false` 下工作。辅助功能权限只在 M4 的粘贴回填才需要。
- **业务规则单一来源。** 命名去重、`pmset` 解析、截图偏好解析、helper 协议、晾衣线时序都在 `kmpDomain`。这些规则各有 Kotlin 测试，跑在 jvm 与 macosArm64 上。Compose 宿主复活时直接复用。
- 界面文案只有一个来源。生成的 `ContractCopy.swift` 之外的 Swift 文件不得写文案字面量，`CopySingleSourceTests` 与 `validate-contract.py` 各拦一次。

### 负面

- 需要自维护 `scripts/build-kmp-framework.sh`。脚本要处理 konanc 路径发现、JRE 定位、依赖 klib 收集。
- konanc 的直接调用绕过了 Amper 的依赖解析。`kmpDomain` 的第三方依赖需要按 `show dependencies` 的输出手工传入。这是本方案最大的维护负担。
- Amper 升级后 konanc 与 JRE 的缓存路径会变。脚本做路径发现，不写死。
- Xcode 工程与 Amper 是两套构建。`./kotlin build` 不会构建 Swift，`xcodebuild` 会调用 Amper。
- Swift 测试跑在宿主 app 进程里。测试期间面板会真的显示在屏幕上。见实测 16。运行时按实测 29 让开，所以测试不改用户机器的截图设置。
- 搬进共享层的规则在 Swift 侧变成跨语言调用。每接一个端口，Swift 就要写一个继承 `NSObject` 的适配器。

### 风险

- 若 `kmpDomain` 引入的依赖增多，klib 收集的出错过概率会上升。缓解办法是限制 `kmpDomain` 的依赖集合，只允许 `kotlinx-serialization` 与 `okio` 这类有 native 产物的库。脚本在缺 klib 时会报出缺失的坐标与期望路径。
- 若后续 Amper 支持 macOS SDK，应切回 `xcode-integration`。届时删除自研脚本。脚本头部留了这条注释。
- 同步目录组要求 Xcode 16 以上，所以 CI 的 Swift 作业不能用更老的运行器。
  M8 把部署目标提到 26.0 之后，这个作业进一步固定 `macos-26`：测试二进制在更低版本的系统上启动不了。
  Kotlin 与合同校验两个作业留在 `macos-15`，它们不构建宿主应用。见实测 31。
- 共享层的类被 `@MainActor` 类型持有后，跨线程传递会过不了 Swift 6 的编译检查。缓解办法是加 `@unchecked Sendable` 门面，并在门面的注释里写清锁由谁持有。见实测 28。

## 备选方案

### 备选 1：macOS 侧领域逻辑用 Swift 重写，KMP 只服务未来平台

放弃 Kotlin/Native 共享。`core` 留在 JVM，服务未来 Windows 与 Android。

代价是 `Engine` 与 `ConfigStore` 等逻辑存在两份实现。长期有漂移风险。

未采纳。原因是用户明确要求 KMP 统一管理，且 konanc 路径已实测可行，Swift 实现 Kotlin interface 也已实测可行。

### 备选 2：Swift Package 加 `swiftc` 手工组装 `.app`

放弃 `project.pbxproj`，用 `Package.swift` 加 `swift test`，再手工拼 `.app` 包。

好处是不用维护 pbxproj。代价是失去 Xcode 的可视化开发与 Instruments 接入。M1 到 M4 要写大量 AppKit 代码，这个代价不划算。

未采纳。

## 未决事项

M0 结案时仍未确认的项目。

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Swift 类实现 Kotlin protocol 并注入 | **已结案**，双向通过 | 见实测 7 |
| `NSScreen.auxiliaryTopLeftArea` 的可用性 | **已结案**，可用且非 nil | 见实测 8 |
| NSPanel 相对系统 UI 的正确 `level` | **已结案**，`.statusBar` = 25 高于菜单栏 24 | 见实测 9 |
| konanc 第三方依赖 klib 的收集方式 | **已结案**，用 `show dependencies` 的输出 | 见实测 6 |
| Amper 能否在 macosArm64 上跑 Kotlin 测试 | **已结案**，能 | 见实测 11。`EngineTest` 可原样迁移，见实测 12 |
| `.mouseMoved` 全局监听在 macOS 27 是否免辅助功能权限 | **已结案，且不再需要** | 注册成功不能作为依据。M1 不用全局监听，改用面板自己的 `NSTrackingArea`。见实测 13 |
| 菜单栏区域该用 `safeAreaInsets.top` 还是 `visibleFrame` 的差 | **已结案**，两处各用其一 | 见实测 15 |

M8（Hub 外壳重做）结案时仍未确认的项目。

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 无边框透明面板里 `glassEffect` 的显示效果 | **待真机确认**。编译通过，外观没看过 | 启动应用，鼠标移到顶部热区，看导航栏与胶囊是不是玻璃。不好看就把 `GlassSurfaceMode.current` 改成 `.material` |
| 搜索框能不能收到键盘输入 | **待真机确认**。`HubPanel.canBecomeKey` 为真，但没有在真机上打过字 | 展开 Hub，在搜索框输入「休眠」，确认有候选结果 |
| Escape 的两段行为 | **决策已结案，键盘通路待真机确认**。见实测 38 | 搜索框有字时按一次 Escape，确认只清搜索；再按一次，确认面板收起 |
| 六个页签的页面高度与内容对得上 | **待真机确认**。几何值有测试，但没有渲染过 | 逐个切页签，看卡片高度与内容有没有被裁 |
| `macos-26` 这个 CI 运行器标签是否可用 | **已结案** | GitHub 文档的 GitHub 托管运行器表里列了 `macos-26`，arm64，macOS 26。作业真的排上了，见实测 37 |
| 部署目标 26.0 的测试作业真的在 CI 上跑通 | **已结案**，378 条全绿 | 见实测 35、实测 36、实测 37。运行器是无刘海的 1024 × 768 屏，写死屏幕坐标的断言在那里失败 |
| 退出按钮的行为 | **待真机确认**。`AppRuntimeTests` 只断言闭包被调用 | 点导航栏底部的退出，确认应用退出且机器状态回到启动前 |

## 参考

- 计划文件：`/Users/wyz/.claude/plans/covio-covio-cheeky-meadow.md`
- 设计合同：`docs/covio-design-contract.json`
- 构建脚本：`scripts/build-kmp-framework.sh`、`scripts/build-macos-swift.sh`、`scripts/test-macos-swift.sh`
- Xcode 工程：`macosApp/Covio.xcodeproj`
