import Foundation

/// Safe command subset from NOOP — excludes destructive opcodes.
enum WhoopCommand: UInt8 {
    case getBatteryLevel = 26
    case toggleRealtimeHR = 3
    case setClock = 10
    case getClock = 11
    case sendR10R11Realtime = 63
    case startRawData = 81
    case stopRawData = 82
    case toggleIMU = 106
    case getHelloHarvard = 35
    case getAdvertisingName = 76
    case getDataRange = 34
    case exitHighFreqSync = 97
}

enum WhoopCommands {
    private static var seq: UInt8 = 1

    private static func nextSeq() -> UInt8 {
        defer { seq &+= 1 }
        return seq
    }

    static func bondWrite(generation: WhoopGeneration) -> Data {
        switch generation {
        case .whoop4:
            return WhoopFraming.buildGen4Command(seq: nextSeq(),
                                                 cmd: WhoopCommand.getBatteryLevel.rawValue,
                                                 payload: [0x00])
        case .whoop5:
            return WhoopFraming.gen5ClientHello
        }
    }

    static func setClock(generation: WhoopGeneration) -> Data {
        let now = UInt32(Date().timeIntervalSince1970)
        let payload: [UInt8] = [
            UInt8(now & 0xFF), UInt8((now >> 8) & 0xFF),
            UInt8((now >> 16) & 0xFF), UInt8((now >> 24) & 0xFF),
            0, 0, 0, 0,
        ]
        return frame(generation: generation, cmd: .setClock, payload: payload)
    }

    /// Live IMU enable. WHOOP 5.0/MG firmware refuses this path — return
    /// nothing so Golf cannot sit on "Arming IMU stream…" after a no-op write.
    static func enableIMUStream(generation: WhoopGeneration) -> [Data] {
        switch generation {
        case .whoop4:
            return [
                frame(generation: .whoop4, cmd: .exitHighFreqSync, payload: [0x00]),
                frame(generation: .whoop4, cmd: .startRawData, payload: [0x01]),
                frame(generation: .whoop4, cmd: .toggleIMU, payload: [0x01]),
                frame(generation: .whoop4, cmd: .sendR10R11Realtime, payload: [0x01]),
            ]
        case .whoop5:
            return []
        }
    }

    /// WHOOP 5.0 high-rate frames arrive via historical offload, not a live
    /// flood. `getDataRange` is the documented probe for that bank.
    static func requestHistoricalOffload(generation: WhoopGeneration) -> [Data] {
        [frame(generation: generation, cmd: .getDataRange, payload: [0x00])]
    }

    static func disableIMUStream(generation: WhoopGeneration) -> [Data] {
        switch generation {
        case .whoop4:
            return [
                frame(generation: .whoop4, cmd: .sendR10R11Realtime, payload: [0x00]),
                frame(generation: .whoop4, cmd: .stopRawData, payload: [0x01]),
                frame(generation: .whoop4, cmd: .toggleIMU, payload: [0x00]),
            ]
        case .whoop5:
            return []
        }
    }

    static func connectHandshake(generation: WhoopGeneration) -> [Data] {
        switch generation {
        case .whoop4:
            return [
                frame(generation: .whoop4, cmd: .getHelloHarvard, payload: [0x00]),
                frame(generation: .whoop4, cmd: .getAdvertisingName, payload: [0x00]),
                setClock(generation: .whoop4),
                frame(generation: .whoop4, cmd: .getClock, payload: []),
                frame(generation: .whoop4, cmd: .sendR10R11Realtime, payload: [0x00]),
                frame(generation: .whoop4, cmd: .getDataRange, payload: [0x00]),
            ]
        case .whoop5:
            // Bond already sent `gen5ClientHello`. Repeating it can stall
            // write-with-response and leave Golf on "Bonded — handshake…".
            return [
                setClock(generation: .whoop5),
                frame(generation: .whoop5, cmd: .getDataRange, payload: [0x00]),
            ]
        }
    }

    private static func frame(generation: WhoopGeneration,
                              cmd: WhoopCommand,
                              payload: [UInt8]) -> Data {
        let s = nextSeq()
        switch generation {
        case .whoop4:
            return WhoopFraming.buildGen4Command(seq: s, cmd: cmd.rawValue, payload: payload)
        case .whoop5:
            return WhoopFraming.buildGen5Command(seq: s, cmd: cmd.rawValue, payload: payload)
        }
    }
}
