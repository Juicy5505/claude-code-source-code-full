import XCTest

final class WhoopFramingTests: XCTestCase {
    func testGen4CommandFrameStartsWithAA() {
        let frame = WhoopFraming.buildGen4Command(seq: 1, cmd: 26, payload: [0x00])
        XCTAssertEqual(frame.first, 0xAA)
        XCTAssertTrue(WhoopFraming.verifyGen4([UInt8](frame)))
    }

    func testGen5ClientHelloValid() {
        let bytes = [UInt8](WhoopFraming.gen5ClientHello)
        XCTAssertTrue(WhoopFraming.verifyGen5(bytes))
    }

    func testParseHeartRate8Bit() {
        let hr = WhoopIMUDecoder.parseHeartRate(Data([0x00, 92]))
        XCTAssertEqual(hr, 92)
    }

    // MARK: - WHOOP 5.0
    //
    // The generation this project actually targets, and the one that had no
    // tests at all: the gen4 path had a flat-gravity case, gen5 had none.

    /// A gen5 packet: 0x2B / subtype 0x15, `count` XYZ int16 triples at offset 20.
    private func gen5Payload(count: Int, x: Int16 = 0, y: Int16 = 0, z: Int16 = 4096) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: 20 + count * 6)
        payload[1] = 0x15
        for i in 0..<count {
            let off = 20 + i * 6
            for (slot, value) in [x, y, z].enumerated() {
                let raw = UInt16(bitPattern: value)
                payload[off + slot * 2] = UInt8(raw & 0xFF)
                payload[off + slot * 2 + 1] = UInt8(raw >> 8)
            }
        }
        return payload
    }

    private func gen5Frame(_ payload: [UInt8]) -> WhoopFrame {
        WhoopFrame(generation: .whoop5, type: 0x2B, seq: 1, cmd: 0, payload: payload)
    }

    func testGen5IMUFlatGravityMagnitude() {
        let samples = WhoopIMUDecoder.samples(from: gen5Frame(gen5Payload(count: 100)),
                                              baseTime: 0)
        XCTAssertEqual(samples.count, 100)
        XCTAssertEqual(samples.first?.magnitudeG ?? 0, 1.0, accuracy: 0.01)
    }

    func testGen5SamplesAreSpacedAtTheStrapRate() {
        // Spacing comes from the strap's rate, not from how many samples landed
        // in this packet. It used to be `1 / count`, which is the same 10 ms
        // only because the length guard below pins count at exactly 100 — two
        // unrelated invariants holding each other up. If the guard is ever
        // loosened to accept partial packets, `1 / count` would spread them
        // across a full second and double every phase duration in them. This
        // pins the spacing so that change cannot happen silently.
        let samples = WhoopIMUDecoder.samples(from: gen5Frame(gen5Payload(count: 100)),
                                              baseTime: 0)
        let step = samples[1].timestamp - samples[0].timestamp
        XCTAssertEqual(step, WhoopIMUDecoder.sampleIntervalS, accuracy: 1e-9)
        // 100 samples at 100 Hz spans the 0.99 s between first and last.
        XCTAssertEqual(samples.last!.timestamp, 0.99, accuracy: 1e-9)
    }

    func testGen5RejectsAPartialPacketRatherThanDecodingPartOfIt() {
        // This guard is why the old `1 / count` never actually fired. Worth a
        // test of its own, so the reason is recorded rather than rediscovered.
        for count in [3, 50, 99] {
            XCTAssertTrue(
                WhoopIMUDecoder.samples(from: gen5Frame(gen5Payload(count: count)),
                                        baseTime: 0).isEmpty,
                "a \(count)-sample packet should be rejected, not partially decoded"
            )
        }
    }

    func testGen5AndGen4AgreeOnSpacing() {
        // Same strap rate, so the same spacing. They disagreed before.
        var gen4 = [UInt8](repeating: 0, count: 1917)
        gen4[14] = 60
        let a = WhoopIMUDecoder.samples(
            from: WhoopFrame(generation: .whoop4, type: 43, seq: 1, cmd: 0, payload: gen4),
            baseTime: 0)
        let b = WhoopIMUDecoder.samples(from: gen5Frame(gen5Payload(count: 100)), baseTime: 0)
        XCTAssertEqual(a[1].timestamp - a[0].timestamp,
                       b[1].timestamp - b[0].timestamp, accuracy: 1e-9)
    }

    func testGen5IgnoresAFrameThatIsNotTheIMUSubtype() {
        // Only 0x2B/0x15 carries motion. Decoding anything else as IMU would
        // turn unrelated telemetry into swings.
        var payload = gen5Payload(count: 100)
        payload[1] = 0x16
        XCTAssertTrue(WhoopIMUDecoder.samples(from: gen5Frame(payload), baseTime: 0).isEmpty)
    }

    func testGen4IMUFlatGravityMagnitude() {
        // Synthetic payload: constant accel Z ≈ 4096 LSB = 1g, X/Y = 0.
        var payload = [UInt8](repeating: 0, count: 1917)
        payload[14] = 72
        for i in 0..<100 {
            let zOff = 482 + i * 2
            payload[zOff] = 0x00
            payload[zOff + 1] = 0x10 // 4096 LE
        }
        let frame = WhoopFrame(generation: .whoop4, type: 43, seq: 10, cmd: 0, payload: payload)
        let samples = WhoopIMUDecoder.samples(from: frame, baseTime: 0)
        XCTAssertEqual(samples.count, 100)
        XCTAssertEqual(samples.first?.magnitudeG ?? 0, 1.0, accuracy: 0.01)
    }
}
