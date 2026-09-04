import Foundation
import IOKit

/// User-space AppleSMC client. Reads usually work; writes often need root.
/// Layout matches Apple PowerManagement's 80-byte SMCParamStruct (dataSize is
/// UInt32, not IOByteCount, so the stride stays 80 on arm64).
struct SMCParamStruct {
    var key: UInt32 = 0
    var versMajor: UInt8 = 0
    var versMinor: UInt8 = 0
    var versBuild: UInt8 = 0
    var versReserved: UInt8 = 0
    var versRelease: UInt16 = 0
    var pLimitVersion: UInt16 = 0
    var pLimitLength: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var b0: UInt8 = 0
    var b1: UInt8 = 0
    var b2: UInt8 = 0
    var b3: UInt8 = 0
    var rest: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

enum SMCClientError: Error {
    case driver
    case notPrivileged
    case keyNotFound
    case failed
}

final class SMCClient: @unchecked Sendable {
    static let paramStride = MemoryLayout<SMCParamStruct>.stride

    private var connection: io_connect_t = 0

    deinit { if connection != 0 { IOServiceClose(connection) } }

    func open() -> Bool {
        if connection != 0 { return true }
        let matching = IOServiceMatching("AppleSMC")
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
                == KERN_SUCCESS
        else { return false }
        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return false }
        let result = IOServiceOpen(device, mach_task_self_, 0, &connection)
        IOObjectRelease(device)
        return result == KERN_SUCCESS && connection != 0
    }

    func keyExists(_ name: String) -> Bool {
        (try? readInfo(name)) != nil
    }

    func readSP78(_ name: String) throws -> Double {
        let size = try readInfo(name)
        var input = SMCParamStruct()
        input.key = Self.fourChar(name)
        input.data8 = 5
        input.dataSize = size
        let output = try call(&input)
        let integer = Double(Int8(bitPattern: output.b0))
        return integer + Double(output.b1) / 256.0
    }

    func writeU8(_ name: String, _ value: UInt8) throws {
        try write(name, bytes: [value], size: 1)
    }

    func writeU32LE(_ name: String, _ value: UInt32) throws {
        let bytes = withUnsafeBytes(of: value.littleEndian) { Array($0) }
        try write(name, bytes: bytes, size: 4)
    }

    private func readInfo(_ name: String) throws -> UInt32 {
        var input = SMCParamStruct()
        input.key = Self.fourChar(name)
        input.data8 = 9
        let output = try call(&input)
        return output.dataSize
    }

    private func write(_ name: String, bytes: [UInt8], size: UInt32) throws {
        var input = SMCParamStruct()
        input.key = Self.fourChar(name)
        input.data8 = 6
        input.dataSize = size
        if bytes.indices.contains(0) { input.b0 = bytes[0] }
        if bytes.indices.contains(1) { input.b1 = bytes[1] }
        if bytes.indices.contains(2) { input.b2 = bytes[2] }
        if bytes.indices.contains(3) { input.b3 = bytes[3] }
        _ = try call(&input)
    }

    private func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        guard open() else { throw SMCClientError.driver }
        var output = SMCParamStruct()
        var outputSize = Self.paramStride
        let kr = IOConnectCallStructMethod(
            connection, 2, &input, Self.paramStride, &output, &outputSize)
        if kr == kIOReturnNotPrivileged { throw SMCClientError.notPrivileged }
        if kr != KERN_SUCCESS { throw SMCClientError.failed }
        if output.result == 132 { throw SMCClientError.keyNotFound }
        if output.result != 0 { throw SMCClientError.failed }
        return output
    }

    static func fourChar(_ name: String) -> UInt32 {
        name.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
}
