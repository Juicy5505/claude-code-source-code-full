import CoreBluetooth

/// GATT map from NOOP / my-whoop reverse-engineering.
enum WhoopUUIDs {
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    enum Gen4 {
        static let service = CBUUID(string: "61080001-8D6D-82B8-614A-1C8CB0F8DCC6")
        static let cmdWrite = CBUUID(string: "61080002-8D6D-82B8-614A-1C8CB0F8DCC6")
        static let cmdNotify = CBUUID(string: "61080003-8D6D-82B8-614A-1C8CB0F8DCC6")
        static let eventNotify = CBUUID(string: "61080004-8D6D-82B8-614A-1C8CB0F8DCC6")
        static let dataNotify = CBUUID(string: "61080005-8D6D-82B8-614A-1C8CB0F8DCC6")
    }

    enum Gen5 {
        static let service = CBUUID(string: "FD4B0001-CCE1-4033-93CE-002D5875F58A")
        static let cmdWrite = CBUUID(string: "FD4B0002-CCE1-4033-93CE-002D5875F58A")
        static let cmdNotify = CBUUID(string: "FD4B0003-CCE1-4033-93CE-002D5875F58A")
        static let eventNotify = CBUUID(string: "FD4B0004-CCE1-4033-93CE-002D5875F58A")
        static let dataNotify = CBUUID(string: "FD4B0005-CCE1-4033-93CE-002D5875F58A")
        static let extraNotify = CBUUID(string: "FD4B0007-CCE1-4033-93CE-002D5875F58A")
    }

    static func generation(for service: CBUUID) -> WhoopGeneration? {
        if service == Gen4.service { return .whoop4 }
        if service == Gen5.service { return .whoop5 }
        return nil
    }
}
