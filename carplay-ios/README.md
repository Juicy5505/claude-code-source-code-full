# NightDrive for iOS + CarPlay

A native iPhone app that connects to your car over a Bluetooth OBD-II adapter and
puts live vehicle metrics **on your existing CarPlay head unit** — speed, RPM,
fuel level with range, coolant temperature, battery voltage, gear, trip, and
odometer.

- **On the phone:** full custom gauge dashboard (analog speedo + tach, warning
  tiles), settings, trip management.
- **On CarPlay:** a tabbed app built from Apple's CarPlay templates — a live
  Gauges panel, a Trip panel, and quick actions (reset trip, connect adapter,
  demo mode, units) — plus a low-fuel alert.

## How CarPlay rules shape this app (read this first)

1. **CarPlay apps must use Apple's template system.** Custom-drawn gauge
   graphics on the car screen are only permitted for navigation-entitled apps
   (that's how Waze draws its map). A vehicle-metrics app fits Apple's
   **"driving task"** category, which gets tab bars, lists, grids, information
   panels, and alerts — that is what the CarPlay side of this app uses.
2. **Waze and Apple Music cannot be embedded** in another CarPlay app. They run
   natively as their own CarPlay apps right next to NightDrive on the car's
   home screen — which is the best version of "all three": full Waze, full
   Apple Music, and NightDrive for everything your car's gauges don't show.
3. **The entitlement is a request, not a purchase.** Apple grants CarPlay
   entitlements per app; see below. The Xcode **CarPlay Simulator works without
   the grant**, so you can develop and see the car screen immediately.

## Requirements

- Mac with Xcode 15+
- Apple Developer account ($99/yr) to run on your own iPhone
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A Bluetooth **LE** ELM327 OBD-II adapter for live car data
  (Vgate iCar Pro *BLE*, Veepeak *BLE+*; classic-Bluetooth-only adapters won't
  pair with iPhones)

## Build & run

```bash
cd carplay-ios
xcodegen generate          # creates NightDrive.xcodeproj from project.yml
open NightDrive.xcodeproj
```

1. In *Signing & Capabilities*, set your team and change the bundle id
   (`com.example.nightdrive`) to your own.
2. Run on your iPhone. Demo mode starts immediately; switch the data source to
   OBD-II in Settings with the adapter plugged in and ignition on.
3. **CarPlay Simulator:** run the app in the iOS Simulator, then
   *I/O → External Displays → CarPlay* to open the car screen.

## Getting the CarPlay entitlement (for your real head unit)

1. Apply at <https://developer.apple.com/contact/carplay/> — request the
   **CarPlay driving task** entitlement, describe the app ("displays live
   vehicle telemetry — speed, fuel, engine data — from the vehicle's OBD-II
   port while driving"), and give the bundle id you chose. Approval typically
   takes a few days to a few weeks.
2. Once granted, Apple attaches the entitlement to your provisioning profile:
   in your developer account create/update the App ID with the CarPlay
   capability, regenerate the profile, and build with it.
3. The entitlements file (`NightDrive/NightDrive.entitlements`) already
   declares `com.apple.developer.carplay-driving-task`.
4. Plug the phone into the car — NightDrive appears on the CarPlay home screen
   next to Waze and Apple Music.

## Project layout

```
carplay-ios/
├── project.yml                     # XcodeGen project definition
└── NightDrive/
    ├── Info.plist                  # phone + CarPlay scene manifest
    ├── NightDrive.entitlements     # CarPlay driving-task entitlement
    ├── App/
    │   ├── AppDelegate.swift       # routes scenes to phone vs. CarPlay
    │   └── PhoneSceneDelegate.swift
    ├── CarPlay/
    │   └── CarPlaySceneDelegate.swift  # tab bar: Gauges / Trip / Actions
    ├── Vehicle/
    │   ├── VehicleDataStore.swift  # shared live state + persistence
    │   ├── OBDManager.swift        # CoreBluetooth ELM327 client
    │   └── DriveSimulator.swift    # demo drive
    └── UI/
        ├── Theme.swift             # NightDrive palette
        ├── RootView.swift
        ├── DashboardView.swift     # gauges + warning tiles
        ├── GaugeView.swift         # 270° analog dial
        └── SettingsView.swift
```

## OBD-II details

The adapter is driven as an ELM327: init sequence `ATZ ATE0 ATL0 ATS0 ATSP0`,
then a 4 Hz round-robin poll of PIDs `010D` (speed), `010C` (RPM), `012F`
(fuel level), `0105` (coolant), and `ATRV` (battery voltage). Known BLE UART
layouts (FFF0/FFF1/FFF2, FFE0/FFE1, and the 128-bit LELink service) are tried
in order, and the app auto-reconnects if the adapter drops.

The web version of this dashboard lives in `../carplay/` and shares the same
design language and OBD protocol.
