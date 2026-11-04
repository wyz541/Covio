import Foundation

/// 判断一个文件是不是 Covio 该收进截图索引的截图。
///
/// 走 Rust core 的 `accepts_shelf_file`，与其它平台共用同一份判断。
/// 判断条件包括扩展名、是否在专属目录里、以及系统有没有打上截图标记。
func hasScreenCaptureAttribute(_ path: String) -> Bool {
    path.withCString { pointer in
        getxattr(pointer, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }
}

/// 监视一个目录，把新出现的截图报出来。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/platform/ScreenshotWatcher.kt`。
/// Kotlin 版用 `WatchService`，这里用 `DispatchSource` 的 vnode 事件。
/// 两者都只看目录本身，不递归子目录。
///
/// 回调送到主队列。截图到达后要改 SwiftUI 状态，而那些状态只能在主线程改。
/// Kotlin 版从监视线程直接回调，因为 Compose 的快照状态允许跨线程写。
final class ScreenshotWatcher: @unchecked Sendable {
    /// 系统写完一张截图需要时间。收到事件后等这么久再读目录。
    static let defaultDebounceSeconds: TimeInterval = 0.200

    private let directory: URL
    private let dedicatedDirectory: URL
    private let requireScreenCaptureAttribute: Bool
    private let debounceSeconds: TimeInterval
    private let attributeReader: (String) -> Bool
    private let onNew: (URL) -> Void
    private let onChange: () -> Void

    private let queue = DispatchQueue(label: "com.wyz.covio.screenshot-watcher")
    private let lock = NSLock()
    private var known: Set<String> = []
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var running = false

    init(
        directory: URL,
        dedicatedDirectory: URL,
        requireScreenCaptureAttribute: Bool = true,
        debounceSeconds: TimeInterval = ScreenshotWatcher.defaultDebounceSeconds,
        attributeReader: @escaping (String) -> Bool = hasScreenCaptureAttribute,
        onNew: @escaping (URL) -> Void,
        onChange: @escaping () -> Void = {}
    ) {
        self.directory = directory
        self.dedicatedDirectory = dedicatedDirectory
        self.requireScreenCaptureAttribute = requireScreenCaptureAttribute
        self.debounceSeconds = debounceSeconds
        self.attributeReader = attributeReader
        self.onNew = onNew
        self.onChange = onChange
    }

    deinit {
        close()
    }

    /// 开始监视。目录不存在时先建一个。建不出来就不启动。
    ///
    /// **不在调用线程上碰文件系统。** 调用方是主线程，而这一步在监视桌面时
    /// 会被系统挡住：桌面在 iCloud 里、家里目录在网络上、或者系统正在等
    /// 用户的隐私授权，`contentsOfDirectory` 都会一直不返回。
    /// 主线程一卡，整个应用就不动了。所以真正的启动放到 `queue` 上。
    func start() {
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()

        queue.async { [weak self] in
            self?.attach()
        }
    }

    /// 真正的启动。跑在 `queue` 上。
    ///
    /// 先记下已有的文件再建事件源，所以事件不会在 `known` 填好之前到达。
    private func attach() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            stopRunning()
            return
        }

        // 启动时先把已有的文件记下来。否则第一次扫描会把旧截图当成新的。
        let existing = listFiles()
        lock.lock()
        known.formUnion(existing.map(canonical))
        let cancelled = !running
        lock.unlock()
        guard !cancelled else { return }

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            stopRunning()
            return
        }

        let created = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        created.setEventHandler { [weak self] in
            guard let self else { return }
            self.settle()
            self.scan()
            // 与 `scan()` 里的 `onNew` 一样送主队列。
            // 事件处理器跑在本类的队列上，直接从这儿回调会让调用方
            // 在主 actor 之外碰 SwiftUI 状态。
            DispatchQueue.main.async { [onChange] in onChange() }
        }
        // 取消处理器负责关闭文件描述符。这里要写全 `Darwin.close`，
        // 否则会撞上本类的 `close()` 方法。
        created.setCancelHandler { Darwin.close(fd) }

        lock.lock()
        // 建好之前就被 `close()` 掉了。
        guard running else {
            lock.unlock()
            created.cancel()
            return
        }
        descriptor = fd
        source = created
        lock.unlock()
        created.resume()
    }

    /// 启动失败或已被取消时把状态收回来。
    private func stopRunning() {
        lock.lock()
        running = false
        lock.unlock()
    }

    /// 停止监视。可以重复调用。
    func close() {
        lock.lock()
        let pending = source
        source = nil
        descriptor = -1
        running = false
        lock.unlock()
        // cancel 之后取消处理器负责关闭文件描述符。
        pending?.cancel()
    }

    /// 扫描一次目录，把新出现的文件报出来。
    ///
    /// 测试直接调这个，不需要真的等文件系统事件。
    func scan() {
        var appeared: [URL] = []
        let current = listFiles().map { file in
            (file: file, key: canonical(file))
        }
        let present = Set(current.map(\.key))
        lock.lock()
        // 删除后的同名文件要能重新识别。
        known.formIntersection(present)
        for entry in current where !known.contains(entry.key) {
            // 系统可能先建文件，再写截图属性。属性还没到时不能记为已处理。
            guard isCandidate(entry.file) else { continue }
            known.insert(entry.key)
            appeared.append(entry.file)
        }
        lock.unlock()

        guard !appeared.isEmpty else { return }
        for file in appeared {
            DispatchQueue.main.async { [onNew] in onNew(file) }
        }
    }

    /// 等系统写完文件。
    ///
    /// 测试里把 `debounceSeconds` 设成 0 就不会真的睡。
    func settle() {
        guard debounceSeconds > 0 else { return }
        Thread.sleep(forTimeInterval: debounceSeconds)
    }

    /// 这个文件要不要收进截图索引。
    func isCandidate(_ path: URL) -> Bool {
        let requireAttribute = requireScreenCaptureAttribute
        let reader = attributeReader
        return ShelfLogic.acceptsShelfFile(
            path: path.path,
            dedicatedDirectory: dedicatedDirectory.path,
            hasScreenCaptureAttribute: { candidate in
                !requireAttribute || reader(candidate)
            }
        )
    }

    private func listFiles() -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.isRegularFile == true
        }
    }

    /// 规范化路径。解析不了符号链接时退回绝对路径。
    private func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
