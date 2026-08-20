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
