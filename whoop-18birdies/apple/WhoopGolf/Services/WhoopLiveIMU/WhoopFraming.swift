import Foundation

/// WHOOP 4.0 / 5.0 BLE frame checksums and envelope parsing.
///
/// Ported from the community NOOP / my-whoop / goose reverse-engineering docs.
/// See whoop-18birdies/WHOOP_REPOS.md and noop-app/noop docs/PROTOCOL.md.
enum WhoopGeneration: String, Codable {
    case whoop4
    case whoop5
}

enum WhoopPacketType: UInt8 {
    case command = 35
    case commandResponse = 36
    case realtimeData = 40
    case realtimeRawData = 43
    case realtimeIMUStream = 51
    case historicalIMUStream = 52
}

struct WhoopFrame {
    let generation: WhoopGeneration
    let type: UInt8
    let seq: UInt8
    let cmd: UInt8
    let payload: [UInt8]
}

enum WhoopFraming {
    private static let crc8Table: [UInt8] = {
        (0..<256).map { i in
            var c = UInt8(i)
            for _ in 0..<8 {
                c = (c & 0x80) != 0 ? (c << 1) ^ 0x07 : c << 1
            }
            return c
        }
    }()

    static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var c: UInt8 = 0
        for b in bytes { c = crc8Table[Int(c ^ b)] }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    static func u16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    static func u32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    static func i16LE(_ bytes: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: u16LE(bytes, offset))
    }

    /// Build a WHOOP 4.0 outbound command frame (type 35).
    static func buildGen4Command(seq: UInt8, cmd: UInt8, payload: [UInt8] = [0x00]) -> Data {
        let inner: [UInt8] = [WhoopPacketType.command.rawValue, seq, cmd] + payload
        let length = UInt16(inner.count + 4)
        let lenBytes: [UInt8] = [UInt8(length & 0xFF), UInt8(length >> 8)]
        let crc = crc32(inner)
        var frame: [UInt8] = [0xAA] + lenBytes + [crc8(lenBytes)] + inner
        frame += [
            UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF),
            UInt8((crc >> 16) & 0xFF), UInt8((crc >> 24) & 0xFF),
        ]
        return Data(frame)
    }

    /// Static WHOOP 5.0 CLIENT_HELLO from NOOP DeviceFamily.whoop5ClientHello.
    static let gen5ClientHello = Data([
        0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71,
        0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D,
    ])

    static func buildGen5Command(seq: UInt8, cmd: UInt8, payload: [UInt8] = [0x00]) -> Data {
        let inner: [UInt8] = [WhoopPacketType.command.rawValue, seq, cmd] + payload
        let declLength = UInt16(inner.count + 4)
        var header: [UInt8] = [0xAA, 0x01,
                               UInt8(declLength & 0xFF), UInt8(declLength >> 8),
                               0x00, 0x01]
        let crc16 = crc16Modbus(header)
        header += [UInt8(crc16 & 0xFF), UInt8(crc16 >> 8)]
        let crc = crc32(inner)
        var frame = header + inner + [
            UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF),
            UInt8((crc >> 16) & 0xFF), UInt8((crc >> 24) & 0xFF),
        ]
        return Data(frame)
    }

    static func verifyGen4(_ frame: [UInt8]) -> Bool {
        guard frame.count >= 11, frame[0] == 0xAA else { return false }
        let length = Int(u16LE(frame, 1))
        guard length + 4 <= frame.count, length >= 7 else { return false }
        guard crc8([frame[1], frame[2]]) == frame[3] else { return false }
        let inner = Array(frame[4..<length])
        return crc32(inner) == u32LE(frame, length)
    }

    static func verifyGen5(_ frame: [UInt8]) -> Bool {
        guard frame.count >= 12, frame[0] == 0xAA, frame[1] == 0x01 else { return false }
        let declLength = Int(u16LE(frame, 2))
        guard declLength + 8 <= frame.count else { return false }
        guard crc16Modbus(Array(frame[0..<6])) == u16LE(frame, 6) else { return false }
        let payloadEnd = declLength + 4
        guard payloadEnd <= frame.count else { return false }
        let inner = Array(frame[8..<payloadEnd])
        return crc32(inner) == u32LE(frame, payloadEnd)
    }

    static func parse(_ frame: [UInt8], generation: WhoopGeneration) -> WhoopFrame? {
        switch generation {
        case .whoop4:
            guard verifyGen4(frame) else { return nil }
            let length = Int(u16LE(frame, 1))
            let inner = Array(frame[4..<length])
            guard inner.count >= 3 else { return nil }
            return WhoopFrame(generation: .whoop4,
                              type: inner[0], seq: inner[1], cmd: inner[2],
                              payload: Array(inner.dropFirst(3)))
        case .whoop5:
            guard verifyGen5(frame) else { return nil }
            let inner = Array(frame[8..<(Int(u16LE(frame, 2)) + 4)])
            guard inner.count >= 3 else { return nil }
            return WhoopFrame(generation: .whoop5,
                              type: inner[0], seq: inner[1], cmd: inner[2],
                              payload: Array(inner.dropFirst(3)))
        }
    }
}

/// Accumulates fragmented BLE notifications into complete 0xAA frames.
final class WhoopReassembler {
    private var buffer: [UInt8] = []

    func append(_ chunk: Data) -> [Data] {
        buffer.append(contentsOf: chunk)
        var frames: [Data] = []
        while let frame = extractOne() {
            frames.append(frame)
        }
        return frames
    }

    private func extractOne() -> Data? {
        guard let start = buffer.firstIndex(of: 0xAA) else {
            buffer.removeAll()
            return nil
        }
        if start > 0 { buffer.removeFirst(start) }
        guard buffer.count >= 4 else { return nil }

        let total: Int
        if buffer.count >= 2, buffer[1] == 0x01 {
            // WHOOP 5.0 Maverick envelope.
            guard buffer.count >= 8 else { return nil }
            total = Int(WhoopFraming.u16LE(buffer, 2)) + 8
        } else {
            total = Int(WhoopFraming.u16LE(buffer, 1)) + 4
        }
        guard total > 0, buffer.count >= total else { return nil }
        let frame = Data(buffer.prefix(total))
        buffer.removeFirst(total)
        return frame
    }
}
