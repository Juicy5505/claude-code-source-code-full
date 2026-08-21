import Combine
import CoreBluetooth
import Foundation

/// Connects to a WHOOP strap, bonds, and attempts a live IMU stream.
///
/// WHOOP 4.0 can flood live type-43 frames after `TOGGLE_IMU`. WHOOP 5.0/MG
/// firmware refuses that live command; high-rate samples arrive later through
/// historical offload (~15 min) and Golf's delayed inbox — not a live spinner.
/// Close the official WHOOP app and put the strap in pairing mode first.
@MainActor
final class WhoopBLEManager: NSObject, ObservableObject {
    @Published var status = "Bluetooth off"
    @Published var bonded = false
    @Published var imuActive = false
    @Published var sessionBusy = false
    @Published var heartRate: Int?
    @Published var peripheralName: String?

    /// Each decoded IMU sample as a motion magnitude in g.
    var onSample: (@MainActor (WhoopIMUDecoder.Sample) -> Void)?
    /// Surfaced when live IMU cannot start; the UI should keep delayed import.
    var onLivePathFailed: (@MainActor (String) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var generation: WhoopGeneration?
    private var cmdWrite: CBCharacteristic?
    private var reassembler = WhoopReassembler()
    private var pendingWrites: [Data] = []
    private var handshakeDone = false
    private var imuArmed = false
    private var sampleBaseTime: TimeInterval = 0
    private var writeInFlight = false
    private var bondStarted = false
    private var cmdNotifyReady = false
    private var dataNotifyReady = false
    private var receivedFrameCount = 0
    private var decodedSampleCount = 0
    private var handshakeWritesRemaining = 0
    private var armingTimer: Timer?
    private var notifyTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func scanAndConnect() {
        guard central.state == .poweredOn else {
            status = "Turn Bluetooth on"
            return
        }
        central.stopScan()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
            peripheral = nil
        }
        resetSession(status: "Scanning for WHOOP…")
        sessionBusy = true
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
    }

    func disconnect() {
        tearDownConnection(status: "Disconnected")
    }

    private func invalidateTimers() {
        armingTimer?.invalidate()
        notifyTimer?.invalidate()
        armingTimer = nil
        notifyTimer = nil
    }

    private func resetSession(status: String) {
        invalidateTimers()
        bonded = false
        imuActive = false
        handshakeDone = false
        imuArmed = false
        writeInFlight = false
        bondStarted = false
        cmdNotifyReady = false
        dataNotifyReady = false
        receivedFrameCount = 0
        decodedSampleCount = 0
        handshakeWritesRemaining = 0
        pendingWrites.removeAll()
        cmdWrite = nil
        generation = nil
        reassembler = WhoopReassembler()
        self.status = status
    }

    private func tearDownConnection(status: String) {
        central.stopScan()
        if let p = peripheral {
            if imuActive, let gen = generation {
                enqueueWrites(WhoopCommands.disableIMUStream(generation: gen))
            }
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        sessionBusy = false
        resetSession(status: status)
    }

    private func enqueueWrites(_ frames: [Data]) {
        guard !frames.isEmpty else { return }
        pendingWrites.append(contentsOf: frames)
        flushWrites()
    }

    private func flushWrites() {
        guard !writeInFlight,
              let p = peripheral,
              let ch = cmdWrite,
              !pendingWrites.isEmpty
        else { return }
        writeInFlight = true
        p.writeValue(pendingWrites.removeFirst(), for: ch, type: .withResponse)
    }

    private func tryStartBondIfReady() {
        guard !bondStarted,
              let gen = generation,
              cmdWrite != nil,
              cmdNotifyReady,
              dataNotifyReady
        else { return }
        bondStarted = true
        notifyTimer?.invalidate()
        notifyTimer = nil
        status = "Bonding…"
        enqueueWrites([WhoopCommands.bondWrite(generation: gen)])
    }

    private func finishAfterHandshake() {
        guard let gen = generation else { return }
        switch gen {
        case .whoop4:
            armLiveIMUStream()
        case .whoop5:
            refuseWhoop5LiveIMU()
        }
    }

    /// WHOOP 4.0 live flood. Never used on 5.0 — firmware refuses `TOGGLE_IMU`.
    private func armLiveIMUStream() {
        guard generation == .whoop4, !imuArmed else { return }
        imuArmed = true
        status = "Arming IMU stream…"
        enqueueWrites(WhoopCommands.enableIMUStream(generation: .whoop4))
        startArmingTimeout()
    }

    /// D7/D8: 5/MG live raw-IMU is firmware-refused. Probe historical range,
    /// never wait on "Arming IMU stream…", never claim LIVE from past frames.
    private func refuseWhoop5LiveIMU() {
        guard !imuArmed else { return }
        imuArmed = true
        status = WhoopLiveIMUPolicy.whoop5ProbingMessage
        enqueueWrites(WhoopCommands.requestHistoricalOffload(generation: .whoop5))
        startWhoop5RefuseTimeout()
    }

    private func scheduleTimer(seconds: TimeInterval, handler: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in
                handler()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func startNotifyTimeout() {
        notifyTimer?.invalidate()
        notifyTimer = scheduleTimer(seconds: WhoopLiveIMUPolicy.notifyTimeoutSeconds) { [weak self] in
            guard let self, !self.bondStarted, self.sessionBusy else { return }
            self.failLivePath(WhoopLiveIMUPolicy.notificationFailureMessage)
        }
    }

    private func startArmingTimeout() {
        armingTimer?.invalidate()
        armingTimer = scheduleTimer(seconds: WhoopLiveIMUPolicy.armingTimeoutSeconds) { [weak self] in
            guard let self, !self.imuActive, self.imuArmed else { return }
            self.failLivePath(
                WhoopLiveIMUPolicy.timeoutMessage(
                    generation: self.generation ?? .whoop4,
                    receivedFrames: self.receivedFrameCount,
                    decodedSamples: self.decodedSampleCount
                )
            )
        }
    }

    private func startWhoop5RefuseTimeout() {
        armingTimer?.invalidate()
        armingTimer = scheduleTimer(seconds: WhoopLiveIMUPolicy.whoop5RefuseTimeoutSeconds) { [weak self] in
            guard let self, !self.imuActive else { return }
            self.failLivePath(
                WhoopLiveIMUPolicy.historicalOffloadResult(sampleCount: self.decodedSampleCount)
            )
        }
    }

    private func startHandshakeTimeout() {
        armingTimer?.invalidate()
        armingTimer = scheduleTimer(seconds: WhoopLiveIMUPolicy.handshakeTimeoutSeconds) { [weak self] in
            guard let self, !self.handshakeDone, self.bonded else { return }
            self.handshakeDone = true
            self.finishAfterHandshake()
        }
    }

    private func failLivePath(_ message: String) {
        onLivePathFailed?(message)
        tearDownConnection(status: message)
    }
}

enum WhoopLiveIMUPolicy {
    static let armingTimeoutSeconds: TimeInterval = 10
    static let notifyTimeoutSeconds: TimeInterval = 5
    static let whoop5RefuseTimeoutSeconds: TimeInterval = 4
    static let handshakeTimeoutSeconds: TimeInterval = 6

    static let notificationFailureMessage =
        "No strap notifications — close the WHOOP app, pairing-mode LEDs, retry"

    static let delayedImportHint =
        "WHOOP 5.0 refuses live IMU — use delayed import (Check for WHOOP swings)"

    static let whoop5ProbingMessage =
        "WHOOP 5.0 live IMU refused — checking historical offload…"

    static let armingStatus = "Arming IMU stream…"

    static func historicalOffloadResult(sampleCount: Int) -> String {
        if sampleCount > 0 {
            return "WHOOP 5.0 live IMU refused. Historical BLE delivered \(sampleCount) samples — use delayed import (Check for WHOOP swings)"
        }
        return delayedImportHint
    }

    static func timeoutMessage(
        generation: WhoopGeneration,
        receivedFrames: Int,
        decodedSamples: Int
    ) -> String {
        if decodedSamples > 0 { return delayedImportHint }
        switch generation {
        case .whoop5:
            return historicalOffloadResult(sampleCount: decodedSamples)
        case .whoop4:
            if receivedFrames == 0 {
                return notificationFailureMessage
            }
            return "No IMU samples — close the WHOOP app, pairing mode, retry"
        }
    }

    static func liveStatus(sampleCount: Int) -> String {
        "IMU live · \(sampleCount) samples"
    }
}

extension WhoopBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if !sessionBusy { status = "Ready — tap Connect" }
            case .unauthorized:
                status = "Bluetooth permission denied"
                sessionBusy = false
            case .poweredOff:
                status = "Bluetooth off"
                sessionBusy = false
            default:
                status = "Bluetooth unavailable"
                sessionBusy = false
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
            self.sessionBusy = false
            self.status = "Connect failed — close WHOOP app, pairing mode, retry"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            guard self.peripheral == nil || self.peripheral?.identifier == peripheral.identifier else { return }
            if self.sessionBusy || self.imuActive || self.bonded {
                self.sessionBusy = false
                self.bonded = false
                self.imuActive = false
                if self.status == WhoopLiveIMUPolicy.armingStatus ||
                    self.status == WhoopLiveIMUPolicy.whoop5ProbingMessage ||
                    (self.imuArmed && !self.imuActive) {
                    self.status = WhoopLiveIMUPolicy.timeoutMessage(
                        generation: self.generation ?? .whoop5,
                        receivedFrames: self.receivedFrameCount,
                        decodedSamples: self.decodedSampleCount
                    )
                } else if !self.status.contains("refuses") &&
                            !self.status.contains("notifications") &&
                            !self.status.contains("No IMU") {
                    self.status = "Disconnected"
                }
            }
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

            var askedForNotify = false
            for ch in service.characteristics ?? [] {
                switch ch.uuid {
                case WhoopUUIDs.Gen4.cmdWrite, WhoopUUIDs.Gen5.cmdWrite:
                    self.cmdWrite = ch
                case WhoopUUIDs.Gen4.cmdNotify, WhoopUUIDs.Gen5.cmdNotify,
                     WhoopUUIDs.Gen4.eventNotify, WhoopUUIDs.Gen5.eventNotify,
                     WhoopUUIDs.Gen4.dataNotify, WhoopUUIDs.Gen5.dataNotify,
                     WhoopUUIDs.Gen5.extraNotify:
                    askedForNotify = true
                    peripheral.setNotifyValue(true, for: ch)
                case WhoopUUIDs.heartRateMeasurement:
                    peripheral.setNotifyValue(true, for: ch)
                default:
                    break
                }
            }
            // Only start the notify timer once, on the vendor command service —
            // HR discovery used to reset it and could strand bonding.
            if askedForNotify, !self.bondStarted, self.notifyTimer == nil {
                self.startNotifyTimeout()
            }
            self.tryStartBondIfReady()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            guard error == nil, characteristic.isNotifying else { return }
            switch characteristic.uuid {
            case WhoopUUIDs.Gen4.cmdNotify, WhoopUUIDs.Gen5.cmdNotify:
                self.cmdNotifyReady = true
            case WhoopUUIDs.Gen4.dataNotify, WhoopUUIDs.Gen5.dataNotify:
                self.dataNotifyReady = true
            default:
                break
            }
            self.tryStartBondIfReady()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            self.writeInFlight = false
            if error != nil {
                self.failLivePath("Write failed — strap may be bonded to WHOOP app")
                return
            }
            if !self.bonded, characteristic.uuid == self.cmdWrite?.uuid {
                self.bonded = true
                self.status = "Bonded — handshake…"
                if let gen = self.generation {
                    let handshake = WhoopCommands.connectHandshake(generation: gen)
                    self.handshakeWritesRemaining = handshake.count
                    self.enqueueWrites(handshake)
                    // WHOOP 5 firmware may ACK the hello and then ignore later
                    // writes. Don't wait forever for handshake completion.
                    self.startHandshakeTimeout()
                }
            } else if self.handshakeWritesRemaining > 0 {
                self.handshakeWritesRemaining -= 1
                if self.handshakeWritesRemaining == 0, !self.handshakeDone {
                    self.handshakeDone = true
                    self.finishAfterHandshake()
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
                self.receivedFrameCount += 1
                self.handle(frame: frame)
            }
        }
    }

    private func handle(frame: WhoopFrame) {
        if frame.type == WhoopPacketType.commandResponse.rawValue {
            handleCommandResponse(frame)
            return
        }

        sampleBaseTime = ProcessInfo.processInfo.systemUptime
        let samples = WhoopIMUDecoder.samples(from: frame, baseTime: sampleBaseTime)
        guard !samples.isEmpty else { return }
        decodedSampleCount += samples.count

        // Historical 5.0 frames are past motion (~15 min bank), not a live
        // flood. Feeding them to the live swing detector would invent shots.
        if generation == .whoop5 {
            status = "Historical IMU · \(decodedSampleCount) samples (not live)"
            return
        }

        imuActive = true
        sessionBusy = true
        armingTimer?.invalidate()
        armingTimer = nil
        status = WhoopLiveIMUPolicy.liveStatus(sampleCount: decodedSampleCount)
        for s in samples {
            if let hr = s.hrBpm { heartRate = hr }
            onSample?(s)
        }
    }

    private func handleCommandResponse(_ frame: WhoopFrame) {
        guard frame.cmd == WhoopCommand.toggleIMU.rawValue else { return }
        // Firmware ACK of a live-IMU toggle with no following type-43 flood
        // is the 5.0 refuse path. Surface it immediately.
        if generation == .whoop5 || frame.payload.first == 0x00 {
            failLivePath(WhoopLiveIMUPolicy.delayedImportHint)
        }
    }
}
