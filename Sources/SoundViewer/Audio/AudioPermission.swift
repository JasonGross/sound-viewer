import Foundation

/// The "System Audio Recording" privacy permission that process taps need.
///
/// There's no public API to check it, so this uses the TCC framework's preflight/request calls
/// (the same approach as Apple-sample-derived tools such as AudioCap). If they're unavailable,
/// we report `.authorized` and let tap creation trigger the system prompt itself.
enum AudioPermission {
    enum Status: Equatable {
        case notDetermined, authorized, denied
    }

    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static func status() -> Status {
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessPreflight") else { return .authorized }
        switch unsafeBitCast(symbol, to: PreflightFn.self)(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// Shows the system prompt if the user hasn't decided yet. Calls back on the main queue.
    static func request(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessRequest") else {
            DispatchQueue.main.async { completion(true) }
            return
        }
        unsafeBitCast(symbol, to: RequestFn.self)(service, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
}
