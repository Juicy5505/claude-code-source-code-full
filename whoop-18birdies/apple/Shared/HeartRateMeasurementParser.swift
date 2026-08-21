import Foundation

struct HeartRateMeasurement: Equatable, Sendable {
    let beatsPerMinute: Int
    let rrIntervalsSeconds: [Double]
}

enum HeartRateMeasurementParser {
    static func parse(_ data: Data) -> HeartRateMeasurement? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }

        let flags = bytes[0]
        var index = 1
        let bpm: Int
        if flags & 0x01 != 0 {
            guard bytes.count >= 3 else { return nil }
            bpm = Int(bytes[1]) | Int(bytes[2]) << 8
            index = 3
        } else {
            bpm = Int(bytes[1])
            index = 2
        }
        guard (1...250).contains(bpm) else { return nil }

        if flags & 0x08 != 0 {
            guard bytes.count >= index + 2 else { return nil }
            index += 2
        }

        var intervals: [Double] = []
        if flags & 0x10 != 0 {
            while index + 1 < bytes.count {
                let value = Int(bytes[index]) | Int(bytes[index + 1]) << 8
                intervals.append(Double(value) / 1024)
                index += 2
            }
        }
        return HeartRateMeasurement(beatsPerMinute: bpm, rrIntervalsSeconds: intervals)
    }
}

