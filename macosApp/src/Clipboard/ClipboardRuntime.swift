import AppKit
import Foundation

/// 剪切板里可以改键的两个动作。
///
/// 编号沿用 [GlobalHotKey] 里对应的 `Spec`，不能另起一套：
/// Carbon 按编号分派，编号重了动作会串。
///
/// 不实现 `Identifiable`：这个枚举整体在主 actor 上，而 `Identifiable`
/// 的要求是非隔离的，Swift 6 会判成跨隔离一致性。界面用 `id: \.rawValue` 代替。
@MainActor
enum ClipboardHotKeyAction: String, CaseIterable {
    /// ⇧⌘V：依次粘贴粘贴栈里的下一条。
    case pasteStack
    /// ⇧⌘C：把前台应用的选中内容收进剪切板。
    case captureSelection

    var hotKeyID: UInt32 { defaultSpec.id }

    /// 出厂组合。
    var defaultSpec: GlobalHotKey.Spec {
        switch self {
        case .pasteStack: GlobalHotKey.pasteStack
        case .captureSelection: GlobalHotKey.captureSelection
        }
    }

    /// 可供用户挑选的组合。第一项是出厂组合。
    ///
    /// 不做自由录制：录制要拦下系统键盘事件，还要处理非法组合与中途退出。
    /// 这四组都不与 macOS 的常用快捷键冲突。
    var candidates: [String] {
        switch self {
        case .pasteStack: ["shift+cmd+V", "shift+cmd+B", "control+shift+V", "option+cmd+V"]
        case .captureSelection: ["shift+cmd+C", "shift+cmd+X", "control+shift+C", "option+cmd+C"]
        }
    }
}

/// 快捷键的注册与注销。
///
/// 默认走 Carbon 的 [GlobalHotKeyCenter]。测试传假的，理由有两条：
///
/// 1. Carbon 的组合是全局占用的。宿主应用在测试进程里也跑起来了，
///    已经占住 ⇧⌘V 与 ⇧⌘C，测试造不出别的应用来抢。
/// 2. 每个应用只装一个 Carbon 事件处理器，多个注册中心装不下。
@MainActor
struct HotKeyRegistrar {
    /// 注册一个组合。失败返回 false。
    var add: (GlobalHotKey.Spec, @escaping @MainActor () -> Void) -> Bool
    /// 注销一个组合。没注册过时要当成功。
    var remove: (GlobalHotKey.Spec) -> Void

    static let carbon = HotKeyRegistrar(
        add: { spec, action in GlobalHotKeyCenter.shared.add(spec: spec, action: action) },
        remove: { GlobalHotKeyCenter.shared.remove(spec: $0) }
    )
}

/// 剪切板运行时要用的外部能力。测试传假的。
@MainActor
struct ClipboardEnvironment {
    /// 配置里的剪切板开关。关掉时停止记录。
    var isEnabled: () -> Bool = { false }
    /// 某个动作当前绑定的组合，写法见 `GlobalHotKey.Spec.binding`。来自配置。
    var hotKeyBinding: (ClipboardHotKeyAction) -> String = { $0.candidates[0] }
    /// 界面语言。OCR 与错误文案要用。
    var language: () -> AppLanguage = { AppLanguage.fromCode(nil) }
    /// 当前时间，秒。
    var now: () -> Int64 = { Int64(Date().timeIntervalSince1970) }
    /// 当前前台应用。粘贴回填要发给它。
    var frontmostApplication: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    /// 识别图片里的文字。默认走 Vision。
    var recognizeText: (URL, @escaping @MainActor (String) -> Void) -> Void = { url, completion in
        ClipboardOCR.recognizeText(in: url, completion: completion)
    }
    /// 合成 ⌘V。默认走 `CGEvent`。
    var paste: (pid_t) -> Bool = { ClipboardPaste.paste(into: $0) }
    /// 辅助功能权限是否已给。
    var hasAccessibilityPermission: () -> Bool = { ClipboardPaste.hasAccessibilityPermission }
    /// 弹出授权引导。
    var requestAccessibilityPermission: () -> Void = { ClipboardPaste.requestAccessibilityPermission() }
}

/// 剪切板回报错误的中间人。
///
/// 与 `ShelfBridge` 同一个理由：`ClipboardRuntime` 的环境闭包要在
/// `self` 全部属性赋值完之前交出去，那时还不能捕获 `AppRuntime`。
@MainActor
final class ClipboardBridge {
    var config: AppConfig
    /// 错误出口。`AppRuntime` 在 `start()` 里接上。
    var report: ((LocalizedCopy) -> Void)?

    init(config: AppConfig) {
        self.config = config
    }
}

/// 剪切板的运行时。对应 M4 的数据与行为层。
///
/// 职责：
/// - 监视系统剪贴板，把新内容收进列表，读写 `clipboard.json`。
/// - 置顶、删除、清空、暂停记录。
/// - 粘贴栈：⇧⌘V 依次把栈里的下一条写回剪贴板并合成 ⌘V。
/// - 图片条目落盘并走一次 OCR。
///
/// 只跑在主线程。图片落盘与 OCR 在后台。
@MainActor
@Observable
final class ClipboardRuntime {
    /// 条目列表，最新的在前。
    private(set) var items: [ClipItem] = []
    /// 待粘贴顺序。元素是 `ClipItem.id`。
    private(set) var pasteStack: [String] = []
    /// 是否暂停记录。
    private(set) var isPaused = false
    /// 保留策略。
    private(set) var policy: ClipPolicy = ClipPolicy.companion.defaults()
    /// 最近一次失败。界面读完应调用 `clearError`。
    private(set) var errorMessage: LocalizedCopy?
    /// 注册失败的快捷键编号。设置页据此提示改键。
    private(set) var failedHotKeys: Set<UInt32> = []

    private let store: ClipboardStore
    private let imageDirectory: URL
    /// 读写的剪贴板。默认系统剪贴板；测试传私有的那个。
    private let pasteboard: NSPasteboard
    /// 快捷键的注册表。默认走 Carbon；测试传假的。
    private let hotKeys: HotKeyRegistrar
    private let environment: ClipboardEnvironment
    private let bridge: ClipboardBridge
    private var monitor: ClipboardMonitor?
    /// 已经注册成功的组合。
    private var registeredHotKeys: [GlobalHotKey.Spec] = []
    private var activationObserver: NSObjectProtocol?
    private var lastExternalPID: pid_t?

    init(
        store: ClipboardStore,
        imageDirectory: URL,
        pasteboard: NSPasteboard = .general,
        hotKeys: HotKeyRegistrar = .carbon,
        environment: ClipboardEnvironment = ClipboardEnvironment(),
        bridge: ClipboardBridge
    ) {
        self.store = store
        self.imageDirectory = imageDirectory
        self.pasteboard = pasteboard
        self.hotKeys = hotKeys
        self.environment = environment
        self.bridge = bridge

        let state = store.load()
        self.items = state.items
        self.pasteStack = state.pasteStack
        self.isPaused = state.paused
        self.policy = state.policy
        self.lastExternalPID = environment.frontmostApplication()?.processIdentifier
    }

    /// 停止记录。面板收起时调用。
    func stop() {
        monitor?.stop()
        monitor = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        for spec in registeredHotKeys {
            hotKeys.remove(spec)
        }
        registeredHotKeys.removeAll()
        failedHotKeys.removeAll()
    }

    /// 读取配置之后重新起停。与 `ShelfRuntime.applyConfiguration()` 同一个作用。
    func applyConfiguration() {
        if environment.isEnabled(), !isPaused {
            start()
        } else {
            stop()
        }
    }

    /// 接收一条新内容。监视器与新条目都由它落地。
    func capture(_ payload: ClipboardPayload) {
        guard environment.isEnabled(), !isPaused else { return }
        guard let item = makeItem(payload) else { return }

        // 同一个内容又复制了一次就把它挪到最前，不新增一条。
        items.removeAll { $0.identity == item.identity }
        items.insert(item, at: 0)
        pruneAndSave()
        startOCRIfNeeded(for: item)
    }

    func togglePin(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        items[index] = Self.remake(item, pinned: !item.pinned)
        pruneAndSave()
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        pasteStack.removeAll { $0 == id }
        pruneAndSave()
    }

    func clearAll() {
        // 置顶的留着。用户明确说过要保住它们。
        items.removeAll { !$0.pinned }
        let live = Set(items.map(\.id))
        pasteStack.removeAll { !live.contains($0) }
        pruneAndSave()
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        save()
        applyConfiguration()
    }

    func clearError() {
        errorMessage = nil
    }

    /// 复制一条到系统剪贴板。不改前台应用。
    @discardableResult
    func copyToPasteboard(_ id: String) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        guard ClipboardWriter.write(item, to: pasteboard) else {
            errorMessage = ContractCopy.copyClipboardErrorImage
            return false
        }
        monitor?.ignoreOwnChange()
        return true
    }

    /// 粘贴回填：复制这一条，再朝前台应用发一次 ⌘V。
    @discardableResult
    func paste(_ id: String) -> Bool {
        guard copyToPasteboard(id) else { return false }
        guard let pid = targetPID() else {
            errorMessage = ContractCopy.copyClipboardErrorPaste
            return false
        }
        guard environment.hasAccessibilityPermission() else {
            // 没有权限时先弹系统引导。内容已经进了剪贴板，用户手动 ⌘V 也能用。
            environment.requestAccessibilityPermission()
            errorMessage = ContractCopy.copyClipboardErrorAccessibility
            return false
        }
        guard environment.paste(pid) else {
            errorMessage = ContractCopy.copyClipboardErrorPaste
            return false
        }
        return true
    }

    /// 粘贴栈的队首。⇧⌘V 走这条。
    @discardableResult
    func pasteNextFromStack() -> Bool {
        // 桥接层返回的配对值不是 Swift 元组，不能直接解构。
        // `first` 是剩下的栈，`second` 是队首。
        let next = ClipboardLogic.shared.nextPaste(state: currentState())
        pasteStack = next.first.pasteStack
        save()
        guard let item = next.second else { return false }
        return paste(item.id)
    }

    /// 入栈。界面上的「稍后粘贴」走这条。
    func pushToStack(_ id: String) {
        pasteStack = ClipboardLogic.shared.pushPasteStack(stack: pasteStack, id: id)
        save()
    }

    /// 注册全局快捷键。失败时记下来，设置页读 [failedHotKeys]。
    ///
    /// Carbon 与别的应用冲突时静默失败，所以必须把结果暴露出去。
    func registerHotKeys() {
        guard registeredHotKeys.isEmpty else { return }
        for action in ClipboardHotKeyAction.allCases {
            let spec = hotKeySpec(for: action)
            let registered = hotKeys.add(spec) { [weak self] in
                self?.perform(action)
            }
            if registered {
                registeredHotKeys.append(spec)
            } else {
                failedHotKeys.insert(action.hotKeyID)
                bridge.report?(ContractCopy.copyClipboardErrorHotKey)
            }
        }
    }

    /// 按配置重新注册全部快捷键。改键之后调用。
    ///
    /// 必须先注销旧的：Carbon 认的是组合本身，
    /// 不注销就直接注册新的，旧组合会继续抢按键。
    func reloadHotKeys() {
        for spec in registeredHotKeys {
            hotKeys.remove(spec)
        }
        registeredHotKeys.removeAll()
        failedHotKeys.removeAll()
        // 记录停着的时候不注册。这时用户关掉了剪切板或按了暂停。
        guard monitor != nil else { return }
        registerHotKeys()
    }

    /// 某个动作当前用的组合。配置里写坏了就退回出厂组合。
    func hotKeySpec(for action: ClipboardHotKeyAction) -> GlobalHotKey.Spec {
        GlobalHotKey.Spec(binding: environment.hotKeyBinding(action), id: action.hotKeyID)
            ?? action.defaultSpec
    }

    /// 某个动作是否注册失败。设置页据此提示改键。
    func hasHotKeyConflict(_ action: ClipboardHotKeyAction) -> Bool {
        failedHotKeys.contains(action.hotKeyID)
    }

    private func perform(_ action: ClipboardHotKeyAction) {
        switch action {
        case .pasteStack: pasteNextFromStack()
        case .captureSelection: captureFrontmostSelection()
        }
    }

    /// ⇧⌘C：让前台应用把选中内容复制到剪贴板，随后监视器会收到它。
    ///
    /// 本应用不直接读别人的选中内容：那需要辅助功能权限，
    /// 而合成一次 ⌘C 让应用自己复制是更省权限的做法。
    func captureFrontmostSelection() {
        guard environment.isEnabled(), !isPaused else { return }
        guard let pid = targetPID() else { return }
        guard environment.hasAccessibilityPermission() else {
            environment.requestAccessibilityPermission()
            errorMessage = ContractCopy.copyClipboardErrorAccessibility
            return
        }
        _ = ClipboardPaste.copySelection(in: pid)
    }

    // MARK: - 内部

    private func start() {
        guard monitor == nil else { return }
        observeActivation()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, imageDirectory: imageDirectory) {
            [weak self] payload in
            self?.capture(payload)
        }
        monitor.start()
        self.monitor = monitor
        registerHotKeys()
    }

    /// 记住最后一个不是 Covio 的前台应用。
    ///
    /// 粘贴时要发给它。Hub 是非激活面板，正常情况下前台应用不变，
    /// 但用户可能在 Hub 打开期间点了别处。与其猜，不如跟着系统事件走。
    private func observeActivation() {
        guard activationObserver == nil else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            // 通知固定送主队列，但闭包是 `@Sendable`。
            MainActor.assumeIsolated {
                guard let self, let application else { return }
                guard application.processIdentifier != ownPID else { return }
                self.lastExternalPID = application.processIdentifier
            }
        }
    }

    /// 粘贴要发给谁。优先当前前台应用，是 Covio 自己就退回上一个外部应用。
    private func targetPID() -> pid_t? {
        let frontmost = environment.frontmostApplication()
        if let frontmost, frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            return frontmost.processIdentifier
        }
        return lastExternalPID
    }

    private func makeItem(_ payload: ClipboardPayload) -> ClipItem? {
        let item = ClipItem(
            id: UUID().uuidString,
            kind: payload.kind,
            text: payload.text,
            filePath: payload.filePath,
            byteSize: payload.byteSize,
            createdAtEpochSeconds: environment.now(),
            pinned: false,
            sourceBundleId: environment.frontmostApplication()?.bundleIdentifier ?? ""
        )
        return item.isUsable ? item : nil
    }

    /// 图片条目收进来之后补一次文字识别。识别结果写回同一个条目的 `text`。
    private func startOCRIfNeeded(for item: ClipItem) {
        guard item.kind == ClipKind.image, !item.filePath.isEmpty else { return }
        let url = URL(fileURLWithPath: item.filePath)
        let id = item.id
        environment.recognizeText(url) { [weak self] text in
            guard let self, !text.isEmpty else { return }
            guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[index] = Self.remake(self.items[index], text: text)
            self.save()
        }
    }

    private func pruneAndSave() {
        let pruned = ClipboardLogic.shared.prune(
            items: items,
            policy: policy,
            nowEpochSeconds: environment.now(),
            exists: { path in FileManager.default.fileExists(atPath: path) }
        )
        items = pruned
        let live = Set(items.map(\.id))
        pasteStack.removeAll { !live.contains($0) }
        save()
    }

    private func currentState() -> ClipboardState {
        ClipboardState(
            items: items,
            pasteStack: pasteStack,
            paused: isPaused,
            policy: policy
        )
    }

    private func save() {
        _ = store.save(state: currentState())
    }

    /// 换一个字段重建条目。桥接模型在 Swift 中字段只读，只能调用 `doCopy`。
    /// 参数要写全，所以集中在这一处。
    private static func remake(
        _ item: ClipItem,
        text: String? = nil,
        pinned: Bool? = nil
    ) -> ClipItem {
        ClipItem(
            id: item.id,
            kind: item.kind,
            text: text ?? item.text,
            filePath: item.filePath,
            byteSize: item.byteSize,
            createdAtEpochSeconds: item.createdAtEpochSeconds,
            pinned: pinned ?? item.pinned,
            sourceBundleId: item.sourceBundleId
        )
    }
}
