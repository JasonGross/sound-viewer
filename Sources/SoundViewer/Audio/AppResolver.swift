import AppKit
import Darwin
import SoundCore

/// Who a lane belongs to, as a person would recognize it.
struct AppIdentity {
    enum Icon {
        case image(NSImage)
        case symbol(String)
    }

    /// Lanes are keyed by this, so all processes with the same key share a lane.
    let key: String
    let name: String
    let icon: Icon
    /// The actual process, for tooltips ("via Google Chrome Helper").
    let processName: String
}

/// Maps audio processes to the apps responsible for them.
@MainActor
final class AppResolver {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

    /// Private but long-standing libSystem function; it's what Activity Monitor uses to attribute
    /// XPC services (e.g. WebKit's GPU process) to the app that launched them.
    private let responsibleFn: ResponsibleFn? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFn.self)
    }()

    private var cache: [pid_t: AppIdentity] = [:]

    func identity(pid: pid_t, bundleID: String) -> AppIdentity {
        if let cached = cache[pid] { return cached }
        let resolved = resolve(pid: pid, bundleID: bundleID)
        cache[pid] = resolved
        return resolved
    }

    func forget(pid: pid_t) { cache[pid] = nil }

    private func resolve(pid: pid_t, bundleID: String) -> AppIdentity {
        let path = executablePath(pid)
        let processName = path.map { ($0 as NSString).lastPathComponent }
            ?? (bundleID.isEmpty ? "pid \(pid)" : bundleID)

        // 1. Inside an app bundle (the app itself, or a helper nested in it).
        if let path, let bundle = AppNaming.outermostAppBundle(inExecutablePath: path) {
            return appIdentity(bundlePath: bundle, processName: processName)
        }
        // 2. A shared system XPC service (e.g. com.apple.WebKit.GPU) working for an app.
        if let path, path.contains(".xpc/"),
           let responsible = responsibleFn?(pid), responsible > 0, responsible != pid,
           let responsiblePath = executablePath(responsible),
           let bundle = AppNaming.outermostAppBundle(inExecutablePath: responsiblePath) {
            return appIdentity(bundlePath: bundle, processName: processName)
        }
        // 3. No path (process already gone), but Core Audio told us an app bundle ID.
        if path == nil, !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return appIdentity(bundlePath: url.path, processName: processName)
        }
        // 4. A plain process: a daemon or command-line tool.
        return AppIdentity(
            key: AppNaming.groupKey(bundleID: nil, processName: processName),
            name: AppNaming.systemDisplayName(forProcessName: processName) ?? processName,
            icon: .symbol(Self.symbol(forProcessName: processName)),
            processName: processName
        )
    }

    private func appIdentity(bundlePath: String, processName: String) -> AppIdentity {
        var name = FileManager.default.displayName(atPath: bundlePath)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        let bundleID = Bundle(path: bundlePath)?.bundleIdentifier
        return AppIdentity(
            key: AppNaming.groupKey(bundleID: bundleID, processName: name),
            name: name,
            icon: .image(NSWorkspace.shared.icon(forFile: bundlePath)),
            processName: processName
        )
    }

    private func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func symbol(forProcessName name: String) -> String {
        switch name {
        case "systemsoundserverd", "usernoted": return "bell.fill"
        case "PowerChime": return "bolt.fill"
        case "universalaccessd", "heard": return "accessibility"
        case "corespeechd", "com.apple.speech.speechsynthesisd": return "waveform.and.mic"
        case "avconferenced", "callservicesd": return "phone.fill"
        case "AirPlayXPCHelper": return "airplayaudio"
        default: return "gearshape.fill"
        }
    }
}
