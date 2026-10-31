import Darwin
import Foundation

/// Launches and stops the OmniRoute process that RouteBar owns.
///
/// OmniRoute runs through the user's login shell so a global `omniroute`
/// install (npm, Homebrew, nvm) is found even though apps started from Finder
/// get a minimal PATH. When it is not installed, `npx` fetches it. The child
/// leads its own process group so stopping it also ends the `node` it spawns.
public final class ServerProcess: @unchecked Sendable {
    public let logURL: URL
    private let lock = NSLock()
    private var pid: pid_t?

    public init(logURL: URL = ServerProcess.defaultLogURL) {
        self.logURL = logURL
    }

    public static var defaultLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RouteBar/omniroute.log")
    }

    static let launchScript = """
    if command -v omniroute >/dev/null 2>&1; then \
    exec omniroute --port \(OmniRoute.port) --no-open; \
    else exec npx -y omniroute --port \(OmniRoute.port) --no-open; fi
    """

    /// True while a process RouteBar started is still alive.
    public var isRunning: Bool {
        lock.withLock {
            guard let pid else { return false }
            if kill(pid, 0) == 0 || errno == EPERM {
                var status: Int32 = 0
                if waitpid(pid, &status, WNOHANG) == 0 { return true }
            }
            self.pid = nil
            return false
        }
    }

    public func start() throws {
        if isRunning { return }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        let arguments = [shell, "-l", "-c", Self.launchScript]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var child: pid_t = 0
        let result = posix_spawn(&child, shell, &actions, &attributes, &argv, environ)
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: "Could not launch OmniRoute: \(String(cString: strerror(result)))"
            ])
        }
        lock.withLock { pid = child }
    }

    /// Sends SIGTERM to the process group, then SIGKILL after `grace` seconds.
    /// Returns immediately, reaping happens in the background.
    public func stop(grace: TimeInterval = 5) {
        guard let group = lock.withLock({ () -> pid_t? in
            defer { pid = nil }
            return pid
        }) else { return }

        kill(-group, SIGTERM)
        DispatchQueue.global(qos: .utility).async {
            let deadline = Date().addingTimeInterval(grace)
            var status: Int32 = 0
            while Date() < deadline {
                if waitpid(group, &status, WNOHANG) != 0 { return }
                usleep(100_000)
            }
            kill(-group, SIGKILL)
            waitpid(group, &status, 0)
        }
    }

    /// Synchronous variant for app termination, where background work would be cut short.
    public func stopAndWait(grace: TimeInterval = 3) {
        guard let group = lock.withLock({ () -> pid_t? in
            defer { pid = nil }
            return pid
        }) else { return }
        kill(-group, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        var status: Int32 = 0
        while Date() < deadline {
            if waitpid(group, &status, WNOHANG) != 0 { return }
            usleep(50_000)
        }
        kill(-group, SIGKILL)
        waitpid(group, &status, 0)
    }
}
