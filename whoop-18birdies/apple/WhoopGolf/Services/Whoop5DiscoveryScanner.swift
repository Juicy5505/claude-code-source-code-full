import CoreBluetooth
import Foundation

/// A WHOOP 5 advertisement observed without connecting to the peripheral.
///
/// Discovery is intentionally separate from experimental historical offload:
/// this type never initiates a connection, writes a characteristic, or changes
/// the encrypted bond currently owned by the official WHOOP app.
struct Whoop5DiscoveredBand: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let signalStrengthDBM: Int
    let observedAt: Date

    var signalLabel: String {
        switch signalStrengthDBM {
        case (-55)...: "nearby"
        case -72 ..< -55: "in range"
        default: "weak signal"
        }
    }
}

@MainActor
final class Whoop5DiscoveryScanner: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case waitingForBluetooth
        case scanning
        case found(Int)
        case noBandFound
        case bluetoothOff
        case unauthorised
        case unavailable
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var bands: [Whoop5DiscoveredBand] = []

    /// WHOOP 5/MG primary service documented by the audited interoperability
    /// implementation. Scanning for it is passive and does not authenticate.
    private nonisolated(unsafe) static let whoop5Service = CBUUID(
        string: "FD4B0001-CCE1-4033-93CE-002D5875F58A"
    )

    private var central: CBCentralManager?
    private var scanTimeout: Timer?
    private var wantsDiscovery = false

    func discover(scanDuration: TimeInterval = 12) {
        wantsDiscovery = true
        bands = []
        scanTimeout?.invalidate()
        guard let central else {
            state = .waitingForBluetooth
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        beginScan(using: central, duration: scanDuration)
    }

    func stop() {
        wantsDiscovery = false
        scanTimeout?.invalidate()
        scanTimeout = nil
        central?.stopScan()
        state = bands.isEmpty ? .idle : .found(bands.count)
    }

    private func beginScan(using central: CBCentralManager, duration: TimeInterval = 12) {
        guard wantsDiscovery else { return }
        switch central.state {
        case .poweredOn:
            state = .scanning
            central.scanForPeripherals(
                withServices: [Self.whoop5Service],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            scanTimeout?.invalidate()
            scanTimeout = Timer.scheduledTimer(
                withTimeInterval: max(3, min(duration, 30)),
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in self?.finishTimedScan() }
            }
        case .poweredOff:
            state = .bluetoothOff
        case .unauthorized:
            state = .unauthorised
        case .unsupported:
            state = .unavailable
        default:
            state = .waitingForBluetooth
        }
    }

    private func finishTimedScan() {
        central?.stopScan()
        scanTimeout?.invalidate()
        scanTimeout = nil
        wantsDiscovery = false
        state = bands.isEmpty ? .noBandFound : .found(bands.count)
    }

    private func accept(
        peripheralID: UUID,
        name: String?,
        rssi: Int,
        observedAt: Date
    ) {
        // CoreBluetooth uses 127 when RSSI is unavailable. Ignore it rather
        // than presenting a fictional proximity estimate.
        guard (-127...0).contains(rssi), rssi != 127 else { return }
        let candidate = Whoop5DiscoveredBand(
            id: peripheralID,
            displayName: name?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "WHOOP 5 sensor",
            signalStrengthDBM: rssi,
            observedAt: observedAt
        )
        if let index = bands.firstIndex(where: { $0.id == peripheralID }) {
            bands[index] = candidate
        } else {
            bands.append(candidate)
        }
        bands.sort {
            if $0.signalStrengthDBM == $1.signalStrengthDBM {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.signalStrengthDBM > $1.signalStrengthDBM
        }
        state = .found(bands.count)
    }
}

extension Whoop5DiscoveryScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            beginScan(using: central)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        Task { @MainActor in
            accept(
                peripheralID: peripheral.identifier,
                name: advertisedName ?? peripheral.name,
                rssi: RSSI.intValue,
                observedAt: .now
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
