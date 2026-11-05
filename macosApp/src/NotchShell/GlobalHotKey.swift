import Carbon.HIToolbox
import Foundation

/// 全局快捷键。`Control+Option+T` 打开或收起 Hub。
/// M4 又加了 `Shift+Command+V` 与 `Shift+Command+C`。
///
/// 用 Carbon 的 `RegisterEventHotKey`。它不需要辅助功能权限。
///
/// **一个应用只装一个 Carbon 事件处理器。** 每个快捷键各装一个的话，
/// 每个处理器都会收到所有快捷键的按下事件，动作会互相串。
/// 所以处理器装在 [GlobalHotKeyCenter]，按 `EventHotKeyID.id` 分派。
///
/// 与其它应用的快捷键冲突时 Carbon 会静默失败，`register()` 返回 false。
/// 失败的快捷键记在 [GlobalHotKeyCenter.failed]，设置页读它来提示用户。
@MainActor
final class GlobalHotKey {
    /// 一个快捷键的全部参数。
    struct Spec: Hashable {
        /// 虚拟键码。取值见 Carbon 的 `kVK_*`。
        let keyCode: UInt32
        /// 修饰键。取值见 Carbon 的 `cmdKey` / `shiftKey` / `controlKey` / `optionKey`。
        let modifiers: UInt32
        /// 分派用的编号。同一个应用内不能重复。
        let id: UInt32
    }

    /// `Control+Option+T` 打开或收起 Hub。
    static let hubToggle = Spec(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(controlKey | optionKey),
        id: 1
    )

    /// M4：`Shift+Command+V` 依次粘贴粘贴栈里的下一条。
    static let pasteStack = Spec(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey),
        id: 2
    )

    /// M4：`Shift+Command+C` 把当前前台应用的选中内容收进剪切板。
    static let captureSelection = Spec(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey | shiftKey),
        id: 3
    )

    /// 四字符签名 'COVI'，与 Rust core 的 `FOUR_CHAR_COVIO` 一致。
    static let signature: OSType = 0x434F_5649

    let spec: Spec
    private let action: @MainActor () -> Void
    private var registered = false

    /// 默认注册 `Control+Option+T`。
    init(spec: Spec = GlobalHotKey.hubToggle, action: @escaping @MainActor () -> Void) {
        self.spec = spec
        self.action = action
    }

    var isRegistered: Bool { registered }

    /// 注册快捷键。失败时返回 false，不抛异常。重复调用只生效一次。
    @discardableResult
    func register() -> Bool {
        if registered { return true }
        guard GlobalHotKeyCenter.shared.add(spec: spec, action: action) else { return false }
        registered = true
        return true
    }

    func unregister() {
        guard registered else { return }
        registered = false
        GlobalHotKeyCenter.shared.remove(spec: spec)
    }
}

// MARK: - 快捷键的写法

extension GlobalHotKey.Spec {
    /// 字母段的键码。位置就是字母在字母表里的下标。
    ///
    /// 只收字母与数字：快捷键要能写进 `config.json` 让用户手改，
    /// 而且 Carbon 冲突时得换一个组合。功能键暂不支持，认不出就回退默认值。
    private static let letterCodes = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
        kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
        kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
        kVK_ANSI_Y, kVK_ANSI_Z,
    ]

    /// 数字段的键码。位置就是数字本身。
    private static let digitCodes = [
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let digits = Array("0123456789")

    /// 从配置里的写法解析。认不出时返回 nil，调用方回退到默认组合。
    ///
    /// 认得的修饰键词：`control`/`ctrl`、`option`/`alt`、`shift`、`cmd`/`command`。
    /// 键名是单个字母或数字，不分大小写。至少要有一个修饰键，
    /// 否则注册出来的是一个裸键，会把整个键盘上的那个键抢走。
    init?(binding: String, id: UInt32) {
        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        for part in binding.lowercased().split(separator: "+") {
            switch part.trimmingCharacters(in: .whitespaces) {
            case "control", "ctrl": modifiers |= UInt32(controlKey)
            case "option", "alt": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case let token:
                guard keyCode == nil, let code = Self.keyCode(for: token) else { return nil }
                keyCode = code
            }
        }
        guard let keyCode, modifiers != 0 else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, id: id)
    }

    /// 配置里的写法。修饰键按 `control`、`option`、`shift`、`cmd` 排序。
    var binding: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("cmd") }
        parts.append(keyName ?? keyCode.description)
        return parts.joined(separator: "+")
    }

    /// 界面上的写法。与 macOS 菜单里的符号一致。
    var displayName: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + (keyName ?? "?")
    }

    /// 键码对应的键名。不认识时返回 nil。
    private var keyName: String? {
        if let index = Self.letterCodes.firstIndex(of: Int(keyCode)) {
            return String(Self.alphabet[index])
        }
        if let index = Self.digitCodes.firstIndex(of: Int(keyCode)) {
            return String(Self.digits[index])
        }
        return nil
    }

    /// 键名对应的键码。不认识时返回 nil。
    private static func keyCode(for token: String) -> UInt32? {
        let name = token.uppercased()
        guard name.count == 1, let character = name.first else { return nil }
        if let index = alphabet.firstIndex(of: character) {
            return UInt32(letterCodes[index])
        }
        if let index = digits.firstIndex(of: character) {
            return UInt32(digitCodes[index])
        }
        return nil
    }
}

/// Carbon 事件处理器的宿主。
///
/// 全应用一个实例。持有唯一的 `EventHandlerRef` 与 `id → 动作` 的映射。
@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var handlerRef: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]

    /// 注册失败的快捷键编号。设置页读它提示用户改键。
    private(set) var failed: Set<UInt32> = []

    private init() {}

    /// 装事件处理器。只装一次。
    ///
    /// 回调地址固定，所以用 `Unmanaged.passUnretained(self)` 传实例是安全的。
    private func installHandlerIfNeeded() -> Bool {
        if handlerRef != nil { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else { return false }
        handlerRef = handler
        return true
    }

    func add(spec: GlobalHotKey.Spec, action: @escaping @MainActor () -> Void) -> Bool {
        if refs[spec.id] != nil { return true }
        guard installHandlerIfNeeded() else {
            failed.insert(spec.id)
            return false
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: GlobalHotKey.signature, id: spec.id)
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        // 冲突时 Carbon 不报错也不注册，返回值仍然可能是 noErr。所以还要看 ref。
        guard status == noErr, let ref else {
            failed.insert(spec.id)
            return false
        }
        refs[spec.id] = ref
        actions[spec.id] = action
        failed.remove(spec.id)
        return true
    }

    func remove(spec: GlobalHotKey.Spec) {
        if let ref = refs.removeValue(forKey: spec.id) {
            UnregisterEventHotKey(ref)
        }
        actions.removeValue(forKey: spec.id)
        failed.remove(spec.id)
    }

    /// 按下事件到了。按编号找动作，找不到就报「没处理」。
    fileprivate func dispatch(id: UInt32) -> OSStatus {
        guard let action = actions[id] else { return OSStatus(eventNotHandledErr) }
        action()
        return noErr
    }

    /// Carbon 的 C 回调。不能捕获上下文，所以实例通过 `userData` 传入。
    private static let callback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
        // 快捷键回调在主线程。Carbon 不保证编译器能推断出来，这里显式声明。
        return MainActor.assumeIsolated { center.dispatch(id: hotKeyID.id) }
    }
}
