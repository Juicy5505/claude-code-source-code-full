import CoreBluetooth
import Foundation

@MainActor
final class WhoopHeartRateProvider: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case bluetoothOff
        case unauthorised
        case scanning
        case connecting(String)
        case streaming(String)
        case stale
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var heartRateBPM: Int?
    @Published private(set) var lastObservedAt: Date?
    @Published private(set) var broadcastName: String?

    var hasFreshReading: Bool {
        guard case .streaming = state,
              heartRateBPM != nil,
              let lastObservedAt
        else { return false }
        return Date().timeIntervalSince(lastObservedAt) < 10
    }

    private nonisolated(unsafe) static let heartRateService = CBUUID(string: "180D")
    private nonisolated(unsafe) static let measurementCharacteristic = CBUUID(string: "2A37")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var wantsStreaming = false
    private var staleTimer: Timer?

    func start() {
        wantsStreaming = true
        guard let central else {
            central = CBCentralManager(delegate: self, queue: .main)
            state = .idle
            return
        }
        switch central.state {
        case .poweredOn: scan()
        case .unauthorized: state = .unauthorised
        case .poweredOff: state = .bluetoothOff
        default: state = .idle
        }
    }

    func stop() {
        wantsStreaming = false
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        staleTimer?.invalidate()
        staleTimer = nil
        heartRateBPM = nil
        lastObservedAt = nil
        broadcastName = nil
        state = .idle
    }

    private func scan() {
        guard wantsStreaming, let central else { return }
        state = .scanning
        central.scanForPeripherals(
            withServices: [Self.heartRateService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func refreshStaleTimer() {
        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.wantsStreaming else { return }
                self.heartRateBPM = nil
                // Keep lastObservedAt so the UI can state exactly how old the
                // most recent direct broadcast sample is.
                self.state = .stale
            }
        }
    }
}

extension WhoopHeartRateProvider: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if wantsStreaming { scan() }
            case .poweredOff:
                staleTimer?.invalidate()
                heartRateBPM = nil
                state = .bluetoothOff
            case .unauthorized:
                staleTimer?.invalidate()
                heartRateBPM = nil
                state = .unauthorised
            default: state = .idle
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
        guard advertisedName?.localizedCaseInsensitiveContains("WHOOP") == true else {
            return
        }
        Task { @MainActor in
            self.peripheral = peripheral
            broadcastName = advertisedName
            central.stopScan()
            peripheral.delegate = self
            state = .connecting(advertisedName ?? "WHOOP HR Broadcast")
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices([Self.heartRateService])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            state = .failed(error?.localizedDescription ?? "Could not connect")
            if wantsStreaming { scan() }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            staleTimer?.invalidate()
            heartRateBPM = nil
            if wantsStreaming { scan() } else { state = .idle }
        }
    }
}

extension WhoopHeartRateProvider: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                state = .failed(error.localizedDescription)
                return
            }
            peripheral.services?
                .first(where: { $0.uuid == Self.heartRateService })
                .map { peripheral.discoverCharacteristics([Self.measurementCharacteristic], for: $0) }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                state = .failed(error.localizedDescription)
                return
            }
            guard let measurement = service.characteristics?
                .first(where: { $0.uuid == Self.measurementCharacteristic })
            else {
                state = .failed("Heart-rate measurement is unavailable")
                return
            }
            peripheral.setNotifyValue(true, for: measurement)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == Self.measurementCharacteristic,
              let data = characteristic.value,
              let reading = HeartRateMeasurementParser.parse(data)
        else { return }
        Task { @MainActor in
            heartRateBPM = reading.beatsPerMinute
            lastObservedAt = .now
            let name = peripheral.name ?? broadcastName ?? "WHOOP HR Broadcast"
            broadcastName = name
            state = .streaming(name)
            refreshStaleTimer()
        }
    }
}
