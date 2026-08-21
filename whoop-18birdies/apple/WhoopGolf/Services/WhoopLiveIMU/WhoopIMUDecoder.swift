import Foundation

/// Decode WHOOP strap IMU batches into user-acceleration magnitudes (g).
///
/// WHOOP 4.0: REALTIME_RAW_DATA (type 43) 1917-byte IMU layout from
/// johnmiddleton12/my-whoop FINDINGS.md — validated against motion captures.
/// WHOOP 5.0: 0x2B subtype 0x15 planar accel @ offset 20 (OpenStrap edge).
/// Live type-43 on 5.0/MG is firmware-refused; type 52 historical frames use
/// the same planar layout when they arrive.
enum WhoopIMUDecoder {
    static let gen4AccelScaleG: Double = 1.0 / 4096.0

    struct Sample {
        let timestamp: TimeInterval
        let magnitudeG: Double
        let hrBpm: Int?
    }

    /// Parse a validated frame's inner record into motion samples.
    static func samples(from frame: WhoopFrame, baseTime: TimeInterval) -> [Sample] {
        switch frame.generation {
        case .whoop4:
            return gen4Samples(type: frame.type, payload: frame.payload, baseTime: baseTime)
        case .whoop5:
            return gen5Samples(type: frame.type, payload: frame.payload, baseTime: baseTime)
        }
    }

    /// WHOOP 4.0 REALTIME_RAW_DATA — 1917-byte IMU packet.
    static func gen4Samples(type: UInt8, payload: [UInt8], baseTime: TimeInterval) -> [Sample] {
        guard type == WhoopPacketType.realtimeRawData.rawValue,
              payload.count >= 1085 + 200 else { return [] }

        let hr = payload.count > 14 ? Int(payload[14]) : nil
        let count = 100
        let dt = 1.0 / 100.0
        var out: [Sample] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let ax = Double(WhoopFraming.i16LE(payload, 82 + i * 2)) * gen4AccelScaleG
            let ay = Double(WhoopFraming.i16LE(payload, 282 + i * 2)) * gen4AccelScaleG
            let az = Double(WhoopFraming.i16LE(payload, 482 + i * 2)) * gen4AccelScaleG
            let mag = SwingAnalysis.magnitude(x: ax, y: ay, z: az)
            out.append(Sample(timestamp: baseTime + Double(i) * dt,
                              magnitudeG: mag,
                              hrBpm: i == count - 1 ? hr : nil))
        }
        return out
    }

    /// WHOOP 5.0 IMU — live 0x2B/0x15, plus stream types 51/52 if the same
    /// planar accel layout is present. Type 43 live flood is firmware-refused
    /// on 5.0/MG; type 52 is the historical one-second frame when it arrives.
    static func gen5Samples(type: UInt8, payload: [UInt8], baseTime: TimeInterval) -> [Sample] {
        let isLiveRaw = type == WhoopPacketType.realtimeRawData.rawValue
        let isHistorical = type == WhoopPacketType.historicalIMUStream.rawValue
        let isStream = type == WhoopPacketType.realtimeIMUStream.rawValue || isHistorical
        guard isLiveRaw || isStream else { return [] }
        // OpenStrap live frames tag subtype 0x15. NOOP type-52 historical
        // frames often omit that tag; still try the planar 100 Hz layout.
        let taggedLive = payload.count > 1 && payload[1] == 0x15
        guard taggedLive || isHistorical else { return [] }
        guard payload.count >= 20 + 600 else { return [] }

        let count = min(100, (payload.count - 20) / 6)
        let dt = 1.0 / Double(max(count, 1))
        var out: [Sample] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let off = 20 + i * 6
            let ax = Double(WhoopFraming.i16LE(payload, off)) * gen4AccelScaleG
            let ay = Double(WhoopFraming.i16LE(payload, off + 2)) * gen4AccelScaleG
            let az = Double(WhoopFraming.i16LE(payload, off + 4)) * gen4AccelScaleG
            let mag = SwingAnalysis.magnitude(x: ax, y: ay, z: az)
            out.append(Sample(timestamp: baseTime + Double(i) * dt,
                              magnitudeG: mag,
                              hrBpm: nil))
        }
        return out
    }

    /// Standard BLE 0x2A37 heart rate parse (works without bond).
    static func parseHeartRate(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }
        let flags = bytes[0]
        if (flags & 0x01) != 0 {
            guard bytes.count >= 3 else { return nil }
            return Int(WhoopFraming.u16LE(bytes, 1))
        }
        guard bytes.count >= 2 else { return nil }
        return Int(bytes[1])
    }
}
