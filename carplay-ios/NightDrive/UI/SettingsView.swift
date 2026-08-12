import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: VehicleDataStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Vehicle", value: store.vehicleName)
                Picker("Body style", selection: $store.tankGallons) {
                    Text("4-Door · 20.8 gal").tag(20.8)
                    Text("2-Door · 16.9 gal").tag(16.9)
                }
            } footer: {
                Text("Body style sets the fuel tank size used for the range estimate.")
            }

            Section("Units") {
                Picker("Units", selection: $store.units) {
                    ForEach(VehicleDataStore.Units.allCases) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Source", selection: $store.source) {
                    ForEach(VehicleDataStore.Source.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Adapter", value: store.obdStatus)
            } header: {
                Text("Vehicle data")
            } footer: {
                Text("OBD-II reads live speed, RPM, fuel, coolant, and battery from a Bluetooth LE ELM327 adapter (e.g. Vgate iCar Pro BLE) in your car's OBD port. Demo simulates a drive so you can explore the app and CarPlay screens.")
            }

            Section("Trip") {
                LabeledContent("Trip", value: store.formattedDistance(store.tripMiles))
                LabeledContent("Odometer", value: store.formattedDistance(store.odometerMiles, decimals: 0))
                Button("Reset trip", role: .destructive) { store.resetTrip() }
            }

            Section {
                Link("Waze", destination: URL(string: "https://waze.com/ul")!)
                Link("Apple Music", destination: URL(string: "https://music.apple.com")!)
            } header: {
                Text("Companion apps")
            } footer: {
                Text("On CarPlay, Waze and Apple Music run as their own apps alongside NightDrive — Apple doesn't allow embedding them. These links open them on the phone.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .tint(Theme.accent)
    }
}
