import CarPlay
import Combine
import UIKit

/// CarPlay scene for the "driving task" app category.
///
/// CarPlay apps are built from Apple's templates (custom-drawn gauges are
/// reserved for navigation-entitled apps), so the head-unit UI is a tab bar:
///   • Gauges — live speed / RPM / fuel / coolant / battery
///   • Trip   — trip, odometer, range, economy
///   • Actions — reset trip, connect adapter, switch units
/// Waze and Apple Music run natively as sibling CarPlay apps next to this one.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var gaugesTemplate: CPInformationTemplate?
    private var tripTemplate: CPInformationTemplate?
    private var refresh: AnyCancellable?
    private var warnedLowFuel = false
    private let store = VehicleDataStore.shared

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let gauges = CPInformationTemplate(title: "NightDrive", layout: .twoColumn,
                                           items: gaugeItems(), actions: [])
        gauges.tabTitle = "Gauges"
        gauges.tabImage = UIImage(systemName: "gauge.with.needle")
        gaugesTemplate = gauges

        let trip = CPInformationTemplate(title: "Trip", layout: .twoColumn,
                                         items: tripItems(), actions: [])
        trip.tabTitle = "Trip"
        trip.tabImage = UIImage(systemName: "road.lanes")
        tripTemplate = trip

        let tabBar = CPTabBarTemplate(templates: [gauges, trip, actionsTemplate()])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)

        // CarPlay templates are value-updated: swap the item arrays on a cadence.
        refresh = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshTemplates() }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        refresh?.cancel()
        refresh = nil
        self.interfaceController = nil
    }

    // MARK: Template content

    private func gaugeItems() -> [CPInformationItem] {
        let speed = store.formattedSpeed()
        return [
            CPInformationItem(title: "Speed", detail: "\(speed.value) \(speed.unit)"),
            CPInformationItem(title: "RPM", detail: String(format: "%.0f", store.rpm)),
            CPInformationItem(title: "Fuel", detail: String(format: "%.0f%%  ·  %@ range",
                                                            store.fuelPercent,
                                                            store.formattedDistance(store.rangeMiles, decimals: 0))),
            CPInformationItem(title: "Coolant", detail: store.formattedTemp(store.coolantF)),
            CPInformationItem(title: "Battery", detail: String(format: "%.1f V", store.batteryVolts)),
            CPInformationItem(title: "Gear", detail: store.gear),
        ]
    }

    private func tripItems() -> [CPInformationItem] {
        [
            CPInformationItem(title: "Trip", detail: store.formattedDistance(store.tripMiles)),
            CPInformationItem(title: "Odometer", detail: store.formattedDistance(store.odometerMiles, decimals: 0)),
            CPInformationItem(title: "Range", detail: store.formattedDistance(store.rangeMiles, decimals: 0)),
            CPInformationItem(title: "Data source", detail: store.source == .obd
                ? (store.obdConnected ? "OBD-II · live" : "OBD-II · " + store.obdStatus)
                : "Demo drive"),
        ]
    }

    private func actionsTemplate() -> CPGridTemplate {
        let buttons = [
            CPGridButton(titleVariants: ["Reset Trip"],
                         image: UIImage(systemName: "arrow.counterclockwise")!) { [weak self] _ in
                self?.store.resetTrip()
            },
            CPGridButton(titleVariants: ["Connect OBD"],
                         image: UIImage(systemName: "car.side")!) { [weak self] _ in
                self?.store.source = .obd
            },
            CPGridButton(titleVariants: ["Demo Mode"],
                         image: UIImage(systemName: "play.circle")!) { [weak self] _ in
                self?.store.source = .demo
            },
            CPGridButton(titleVariants: ["Units"],
                         image: UIImage(systemName: "ruler")!) { [weak self] _ in
                guard let self else { return }
                self.store.units = self.store.units == .imperial ? .metric : .imperial
            },
        ]
        let grid = CPGridTemplate(title: "Actions", gridButtons: buttons)
        grid.tabTitle = "Actions"
        grid.tabImage = UIImage(systemName: "square.grid.2x2")
        return grid
    }

    private func refreshTemplates() {
        gaugesTemplate?.items = gaugeItems()
        tripTemplate?.items = tripItems()
        maybeWarnLowFuel()
    }

    private func maybeWarnLowFuel() {
        guard store.fuelPercent < 10, !warnedLowFuel,
              let interfaceController, interfaceController.presentedTemplate == nil else { return }
        warnedLowFuel = true
        let dismiss = CPAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(
            titleVariants: [String(format: "Low fuel — %.0f%% (%@ range)",
                                   store.fuelPercent,
                                   store.formattedDistance(store.rangeMiles, decimals: 0))],
            actions: [dismiss])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }
}
