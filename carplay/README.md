# NightDrive — CarPlay-style driving dashboard

A single-file, browser-based head unit (`index.html`) you can run fullscreen on a
phone or tablet mounted in your car. No build step, no dependencies — open the file
or serve the folder and drive.

## Views

- **Home** — CarPlay-style app grid with live range / fuel / trip readouts.
- **Maps** — canvas turn-by-turn navigation view: heading-up map, next-turn banner,
  ETA bar, and a speed ring that turns red over your configured limit. An
  "Open in Waze" button hands the drive off to the real Waze app.
- **Dashboard** — canvas speedometer and tachometer plus fuel (with range
  estimate), coolant temperature, battery voltage, trip, and odometer tiles with
  amber/red warning states.
- **Music** — now-playing screen with transport controls, seek, and a queue.
  Integrates with the Media Session API (steering-wheel / lock-screen controls)
  and deep-links into Apple Music.
- **Settings** — units (mph/°F or km/h/°C), data source, speed warning, fullscreen.

## Vehicle data sources

| Source | What it reads |
|---|---|
| **Demo** (default) | Simulated city/highway drive: speed, RPM, gear, fuel burn, coolant warm-up, battery. |
| **GPS** | Real speed and heading from the device's geolocation (requires location permission). |
| **OBD-II** | Live speed, RPM, fuel level, coolant temp, and battery voltage from a Bluetooth LE ELM327 adapter (e.g. Vgate iCar Pro BLE) plugged into the car's OBD port. Requires Web Bluetooth (Chrome/Edge on Android or desktop). |

## App tiles

Waze, Apple Music, and Phone tiles deep-link into the native apps via their URL
schemes (`waze://`, `music://`, `tel:`) with web fallbacks. Real CarPlay apps
require Apple entitlements; this dashboard runs anywhere a browser does.

## Notes

- Trip and odometer accrue from whichever speed source is active.
- OBD polling round-robins PIDs `010D` (speed), `010C` (RPM), `012F` (fuel),
  `0105` (coolant), and `ATRV` (battery) at 4 Hz.
- The UI is deliberately dark-only for night-driving glare safety.
