import Combine
import CoreBluetooth
import Foundation

/// Connects to a WHOOP strap, bonds, enables the IMU stream, and publishes
/// motion magnitudes for swing detection.
///
/// Based on noop-app/noop Strand/BLE/BLEManager.swift patterns. Close the
/// official WHOOP app and put the strap in pairing mode before connecting.
@MainActor
final class WhoopBLEManager: NSObject, ObservableObject {
    @Published var status = "Bluetooth off"
    @Published var bonded = false
    @Published var imuActive = false
    @Published var heartRate: Int?
    @Published var peripheralName: String?

    /// Each decoded IMU sample as a motion magnitude in g.
    var onSample: (@MainActor (WhoopIMUDecoder.Sample) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var generation: WhoopGeneration?
    private var cmdWrite: CBCharacteristic?
    private var reassembler = WhoopReassembler()
    private var pendingWrites: [Data] = []
    private var handshakeDone = false
    private var imuArmed = false
    private var sampleBaseTime: TimeInterval = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func scanAndConnect() {
        guard central.state == .poweredOn else {
            status = "Turn Bluetooth on"
            return
        }
        status = "Scanning for WHOOP…"
        bonded = false
        imuActive = false
        handshakeDone = false
        imuArmed = false
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
    }

    func disconnect() {
        if let p = peripheral {
            if imuActive, let gen = generation {
                enqueueWrites(WhoopCommands.disableIMUStream(generation: gen))
            }
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        bonded = false
        imuActive = false
        status = "Disconnected"
    }

    private func enqueueWrites(_ frames: [Data]) {
        pendingWrites.append(contentsOf: frames)
        flushWrites()
    }

    private func flushWrites() {
        guard let p = peripheral, let ch = cmdWrite, !pendingWrites.isEmpty else { return }
        let next = pendingWrites.removeFirst()
        p.writeValue(next, for: ch, type: .withResponse)
    }
}

extension WhoopBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                status = "Ready — tap Connect"
            case .unauthorized:
                status = "Bluetooth permission denied"
            case .poweredOff:
                status = "Bluetooth off"
            default:
                status = "Bluetooth unavailable"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard name.uppercased().contains("WHOOP") else { return }
        Task { @MainActor in
            self.central.stopScan()
            self.peripheral = peripheral
            self.peripheralName = name
            self.status = "Connecting to \(name)…"
            peripheral.delegate = self
            self.central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.status = "Discovering services…"
            peripheral.discoverServices([
                WhoopUUIDs.Gen4.service,
                WhoopUUIDs.Gen5.service,
                WhoopUUIDs.heartRateService,
            ])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.status = "Connect failed — close WHOOP app, pairing mode, retry"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.bonded = false
            self.imuActive = false
            self.status = "Disconnected"
        }
    }
}

extension WhoopBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                if let gen = WhoopUUIDs.generation(for: service.uuid) {
                    self.generation = gen
                }
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            guard let gen = self.generation ?? WhoopUUIDs.generation(for: service.uuid) else { return }
            self.generation = gen

            for ch in service.characteristics ?? [] {
                switch ch.uuid {
                case WhoopUUIDs.Gen4.cmdWrite, WhoopUUIDs.Gen5.cmdWrite:
                    self.cmdWrite = ch
                    self.enqueueWrites([WhoopCommands.bondWrite(generation: gen)])
                case WhoopUUIDs.Gen4.cmdNotify, WhoopUUIDs.Gen5.cmdNotify,
                     WhoopUUIDs.Gen4.eventNotify, WhoopUUIDs.Gen5.eventNotify,
                     WhoopUUIDs.Gen4.dataNotify, WhoopUUIDs.Gen5.dataNotify,
                     WhoopUUIDs.Gen5.extraNotify:
                    peripheral.setNotifyValue(true, for: ch)
                case WhoopUUIDs.heartRateMeasurement:
                    peripheral.setNotifyValue(true, for: ch)
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            if error != nil {
                self.status = "Write failed — strap may be bonded to WHOOP app"
                return
            }
            if !self.bonded, characteristic.uuid == self.cmdWrite?.uuid {
                self.bonded = true
                self.status = "Bonded — handshake…"
                if let gen = self.generation {
                    self.enqueueWrites(WhoopCommands.connectHandshake(generation: gen))
                }
            }
            if self.bonded && !self.handshakeDone && self.pendingWrites.isEmpty {
                self.handshakeDone = true
                if let gen = self.generation, !self.imuArmed {
                    self.imuArmed = true
                    self.imuActive = true
                    self.status = "Arming IMU stream…"
                    self.enqueueWrites(WhoopCommands.enableIMUStream(generation: gen))
                }
            }
            self.flushWrites()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        Task { @MainActor in
            if characteristic.uuid == WhoopUUIDs.heartRateMeasurement {
                self.heartRate = WhoopIMUDecoder.parseHeartRate(data)
                return
            }

            guard let gen = self.generation else { return }
            for frameData in self.reassembler.append(data) {
                let bytes = [UInt8](frameData)
                guard let frame = WhoopFraming.parse(bytes, generation: gen) else { continue }
                self.handle(frame: frame)
            }
        }
    }

    private func handle(frame: WhoopFrame) {
        sampleBaseTime = ProcessInfo.processInfo.systemUptime
        let samples = WhoopIMUDecoder.samples(from: frame, baseTime: sampleBaseTime)
        guard !samples.isEmpty else { return }
        if imuActive { status = "IMU live · \(samples.count) samples" }
        for s in samples {
            if let hr = s.hrBpm { heartRate = hr }
            onSample?(s)
        }
    }
}
