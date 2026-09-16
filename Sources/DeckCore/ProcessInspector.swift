import Darwin
import Foundation

public struct ProcArgs: Equatable, Sendable {
    public let executablePath: String
    public let argv: [String]
    public let env: [String: String]

    public init(executablePath: String, argv: [String], env: [String: String]) {
        self.executablePath = executablePath
        self.argv = argv
        self.env = env
    }
}

public struct ProcUsage: Equatable, Sendable {
    /// Activity Monitor's "Memory" column (`ri_phys_footprint`).
    public var footprintBytes: UInt64
    /// Total user + system CPU time consumed so far.
    public var cpuNanos: UInt64

    public init(footprintBytes: UInt64, cpuNanos: UInt64) {
        self.footprintBytes = footprintBytes
        self.cpuNanos = cpuNanos
    }
}

public struct ProcessEntry: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    /// Seconds since 1970; distinguishes a reused pid from the original process.
    public var startTime: Double

    public init(pid: Int32, ppid: Int32, startTime: Double) {
        self.pid = pid
        self.ppid = ppid
        self.startTime = startTime
    }
}

public protocol ProcessInspecting: Sendable {
    func isAlive(_ pid: Int32) -> Bool
    func startTime(_ pid: Int32) -> Date?
    func args(_ pid: Int32) -> ProcArgs?
    func usage(_ pid: Int32) -> ProcUsage?
    /// Every process on the system (pid, parent, start time).
    func processTable() -> [ProcessEntry]
    /// All descendants of `pid`, deepest first.
    func descendants(of pid: Int32) -> [Int32]
    /// Path of the process's executable (works for other users' processes too, e.g. `login`).
    func executablePath(_ pid: Int32) -> String?
    /// Controlling terminal, e.g. "/dev/ttys003"; nil when the process has none.
    func ttyPath(_ pid: Int32) -> String?
}

public struct SystemProcessInspector: ProcessInspecting {
    public init() {}

    public func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) != 0 && errno != EPERM { return false }
        guard let info = kinfo(pid) else { return false }
        return info.kp_proc.p_stat != SZOMB
    }

    public func startTime(_ pid: Int32) -> Date? {
        guard let info = kinfo(pid) else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    public func args(_ pid: Int32) -> ProcArgs? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        return Self.parseProcArgs(Array(buffer.prefix(size)))
    }

    /// Layout: Int32 argc, exec path, NUL padding, argc NUL-terminated argv strings, then env strings.
    static func parseProcArgs(_ bytes: [UInt8]) -> ProcArgs? {
        guard bytes.count > 4 else { return nil }
        let argc = bytes.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = 4

        func nextString() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count && bytes[index] != 0 { index += 1 }
            let s = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return s
        }

        guard let exec = nextString() else { return nil }
        while index < bytes.count && bytes[index] == 0 { index += 1 }

        var argv: [String] = []
        for _ in 0..<max(0, Int(argc)) {
            guard let arg = nextString() else { break }
            argv.append(arg)
        }

        var env: [String: String] = [:]
        while let entry = nextString(), !entry.isEmpty {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return ProcArgs(executablePath: exec, argv: argv, env: env)
    }

    private static let nanosPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    public func usage(_ pid: Int32) -> ProcUsage? {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard status == 0 else { return nil }
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        return ProcUsage(footprintBytes: info.ri_phys_footprint, cpuNanos: UInt64(ticks * Self.nanosPerTick))
    }

    public func processTable() -> [ProcessEntry] {
        allProcesses().map { proc in
            let tv = proc.kp_proc.p_starttime
            return ProcessEntry(pid: proc.kp_proc.p_pid, ppid: proc.kp_eproc.e_ppid,
                                startTime: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
        }
    }

    public func descendants(of pid: Int32) -> [Int32] {
        ProcessTree(processTable()).descendants(of: pid).reversed()
    }

    public func executablePath(_ pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        // PROC_PIDPATHINFO_MAXSIZE
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }

    public func ttyPath(_ pid: Int32) -> String? {
        guard pid > 0, let info = kinfo(pid) else { return nil }
        let device = info.kp_eproc.e_tdev
        guard device != -1 else { return nil } // NODEV
        var buffer = [CChar](repeating: 0, count: 64)
        guard devname_r(device, S_IFCHR, &buffer, Int32(buffer.count)) != nil else { return nil }
        let name = String(cString: buffer)
        guard !name.isEmpty, name != "??" else { return nil }
        return "/dev/" + name
    }

    private func kinfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private func allProcesses() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        // Headroom for processes spawned between the two calls.
        size += 32 * MemoryLayout<kinfo_proc>.stride
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return Array(procs.prefix(size / MemoryLayout<kinfo_proc>.stride))
    }
}
