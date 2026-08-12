import Foundation
import CoreBluetooth

/// CoreBluetooth client for ELM327-compatible BLE OBD-II adapters
/// (Vgate iCar Pro BLE, Veepeak BLE+, and most FFF0/FFE0 UART clones).
///
/// Protocol: plain ASCII AT/PID commands terminated with '\r'; the adapter
/// answers with hex bytes and signals ready with '>'.
final class OBDManager: NSObject {
    private struct Profile {
        let service: CBUUID
        let notify: CBUUID
        let write: CBUUID
    }

    private let profiles: [Profile] = [
        Profile(service: CBUUID(string: "FFF0"), notify: CBUUID(string: "FFF1"), write: CBUUID(string: "FFF2")),
        Profile(service: CBUUID(string: "FFE0"), notify: CBUUID(string: "FFE1"), write: CBUUID(string: "FFE1")),
        Profile(service: CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"),
                notify: CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F"),
                write: CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")),
    ]

    private unowned let store: VehicleDataStore
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    private var activeProfile: Profile?

    private var buffer = ""
    private var initQueue: [String] = []
    private var pollPids = ["010D", "010C", "012F", "0105", "ATRV"]
    private var pollIndex = 0
    private var pollTimer: Timer?
    private var awaitingResponse = false

    init(store: VehicleDataStore) {
        self.store = store
        super.init()
    }

    func connect() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            status("Starting Bluetooth…")
        } else if central?.state == .poweredOn {
            startScan()
        }
    }

    func disconnect() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        writeCharacteristic = nil
        store.obdConnected = false
        status("Not connected")
    }

    private func status(_ text: String) {
        DispatchQueue.main.async {
            self.store.obdStatus = text
        }
    }

    private func startScan() {
        status("Scanning for OBD-II adapter…")
        central?.scanForPeripherals(withServices: profiles.map(\.service), options: nil)
        // Some clones don't advertise their UART service; widen after 6 s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.peripheral == nil else { return }
            self.central?.scanForPeripherals(withServices: nil, options: nil)
            self.status("Scanning (all devices)… plug the adapter in and turn the ignition on")
        }
    }

    // MARK: Command plumbing

    private func send(_ command: String) {
        guard let peripheral, let characteristic = writeCharacteristic else { return }
        awaitingResponse = true
        peripheral.writeValue(Data((command + "\r").utf8), for: characteristic, type: writeType)
        // Failsafe: never wedge the poll loop on a lost response.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.awaitingResponse = false
        }
    }

    private func startInit() {
        initQueue = ["ATZ", "ATE0", "ATL0", "ATS0", "ATSP0"]
        status("Initializing adapter…")
        sendNextInit()
    }

    private func sendNextInit() {
        guard let cmd = initQueue.first else {
            store.obdConnected = true
            status("Connected · polling live data")
            startPolling()
            return
        }
        initQueue.removeFirst()
        send(cmd)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, !self.awaitingResponse, self.store.source == .obd else { return }
            self.send(self.pollPids[self.pollIndex])
            self.pollIndex = (self.pollIndex + 1) % self.pollPids.count
        }
    }

    // MARK: Response parsing

    private func handleChunk(_ text: String) {
        buffer += text
        guard buffer.contains(">") else { return }
        let response = buffer
        buffer = ""
        awaitingResponse = false

        if store.obdConnected {
            parse(response)
        } else {
            sendNextInit()          // advance the AT init sequence
        }
    }

    private func parse(_ raw: String) {
        let hex = raw.uppercased().filter { "0123456789ABCDEF".contains($0) }

        func byte(afterPrefix prefix: String, width: Int) -> Int? {
            guard let range = hex.range(of: prefix) else { return nil }
            let start = range.upperBound
            guard let end = hex.index(start, offsetBy: width, limitedBy: hex.endIndex) else { return nil }
            return Int(hex[start..<end], radix: 16)
        }

        DispatchQueue.main.async {
            if let v = byte(afterPrefix: "410D", width: 2) {
                self.store.speedMph = Double(v) * 0.621371            // km/h → mph
            } else if let v = byte(afterPrefix: "410C", width: 4) {
                self.store.rpm = Double(v) / 4
            } else if let v = byte(afterPrefix: "412F", width: 2) {
                self.store.fuelPercent = Double(v) * 100 / 255
            } else if let v = byte(afterPrefix: "4105", width: 2) {
                self.store.coolantF = Double(v - 40) * 9 / 5 + 32
            } else if let match = raw.range(of: #"\d{1,2}\.\d"#, options: .regularExpression),
                      raw.contains("V") {
                self.store.batteryVolts = Double(raw[match]) ?? self.store.batteryVolts
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension OBDManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScan()
        case .unauthorized:
            status("Bluetooth permission denied — enable it in Settings")
        case .poweredOff:
            status("Bluetooth is off")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (peripheral.name ?? "").lowercased()
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let matchesService = advertised.contains { uuid in profiles.contains { $0.service == uuid } }
        let looksLikeAdapter = ["obd", "elm", "vgate", "icar", "veepeak", "vlink"].contains { name.contains($0) }
        guard matchesService || looksLikeAdapter else { return }

        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        status("Connecting to \(peripheral.name ?? "adapter")…")
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(profiles.map(\.service))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        pollTimer?.invalidate()
        pollTimer = nil
        writeCharacteristic = nil
        store.obdConnected = false
        status("Adapter disconnected")
        if store.source == .obd { startScan() }        // auto-reconnect while OBD is selected
    }
}

// MARK: - CBPeripheralDelegate

extension OBDManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { svc in
            profiles.contains { $0.service == svc.uuid }
        }) else {
            status("No known UART service on this device")
            return
        }
        activeProfile = profiles.first { $0.service == service.uuid }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let profile = activeProfile, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == profile.notify {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.uuid == profile.write {
                writeCharacteristic = characteristic
                writeType = characteristic.properties.contains(.writeWithoutResponse)
                    ? .withoutResponse : .withResponse
            }
        }
        if writeCharacteristic != nil { startInit() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value,
              let text = String(data: data, encoding: .ascii) else { return }
        handleChunk(text)
    }
}
