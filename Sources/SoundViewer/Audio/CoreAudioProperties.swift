import CoreAudio
import Foundation

struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let operation: String

    var description: String { "\(operation) failed (\(fourCharCode(status)))" }
}

func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, operation: operation()) }
}

/// Renders an OSStatus as its four-character code when it is one ('who?'), else as a number.
func fourCharCode(_ status: OSStatus) -> String {
    let bytes = withUnsafeBytes(of: UInt32(bitPattern: status).bigEndian) { Array($0) }
    if bytes.allSatisfy({ (32...126).contains($0) }) {
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
    return String(status)
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)
}

func propertyAddress(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

/// Typed reads of Core Audio object properties.
enum AudioProperty {
    static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        initial: T) throws -> T {
        var address = propertyAddress(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        try check(status,
                  "reading \(fourCharCode(OSStatus(bitPattern: selector))) of object \(object)")
        return value
    }

    static func readArray<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             element: T) throws -> [T] {
        var address = propertyAddress(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "sizing property")
        var values = [T](repeating: element, count: Int(size) / MemoryLayout<T>.stride)
        guard !values.isEmpty else { return [] }
        let status = values.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!)
        }
        try check(status, "reading array property")
        return Array(values.prefix(Int(size) / MemoryLayout<T>.stride))
    }

    static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = propertyAddress(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "reading string property")
        return value?.takeRetainedValue() as String? ?? ""
    }
}
