import Foundation

/// 单实例锁。
///
/// 单实例锁用文件锁实现。
/// 进程退出或崩溃时，操作系统自动释放锁。
///
/// 当前宿主与旧版宿主使用不同的锁文件名，所以可以同时运行。见 `AppPaths`。
final class SingleInstanceLock {
    private let url: URL
    private var descriptor: Int32 = -1

    init(url: URL = AppPaths.lockFile) {
        self.url = url
    }

    var isAcquired: Bool { descriptor >= 0 }

    /// 尝试取锁。已被其它进程持有时立即返回 false，不等待。
    @discardableResult
    func acquire() -> Bool {
        if descriptor >= 0 { return true }
        // 建锁文件自己的目录。默认路径的父目录就是应用数据目录。
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return false }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }

        descriptor = fd
        return true
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
