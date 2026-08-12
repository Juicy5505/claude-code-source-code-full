"""Live heart rate from a WHOOP strap, over Bluetooth, into the swing logger.

WHOOP 4.0 can broadcast heart rate using the standard Bluetooth Heart Rate
Profile — the same protocol as a Polar chest strap. Enable it once in the
WHOOP app: Menu -> Device Settings -> HR Broadcast -> ON. After that the strap
is just a BLE heart-rate monitor any nearby device can read, including this
phone via Pythonista's `cb` module.

This is the one live signal a WHOOP can contribute during a session. Its raw
accelerometer never leaves WHOOP's pipeline, so it cannot be the swing sensor;
but heart rate at the moment of each swing, and cardio drift across a bucket
or a round, are real physiology measured in real time.

The BLE packet parsing and HRV math are pure Python and tested off-device.
Only the thin `cb` shell is Pythonista-specific.
"""

import time

# Bluetooth SIG assigned numbers for the Heart Rate Profile.
HR_SERVICE_UUID = "180D"
HR_MEASUREMENT_UUID = "2A37"

# Substring (case-insensitive) a peripheral's name must contain. WHOOP straps
# advertise with "WHOOP" in the name.
DEVICE_NAME_CONTAINS = "WHOOP"


# --- Packet parsing (pure, testable) -------------------------------------------


def parse_hr_measurement(data):
    """Decodes a Heart Rate Measurement (0x2A37) notification payload.

    Layout per the Bluetooth spec: a flags byte, then the heart rate as uint8
    or uint16-LE depending on flags bit 0, an optional uint16 energy-expended
    field (flags bit 3), then zero or more uint16-LE RR intervals in units of
    1/1024 s (flags bit 4).

    Returns {"bpm": int, "rr_s": [float, ...]} or None for a malformed packet.
    Never raises: a garbled notification must not take the session down.
    """
    if not data or len(data) < 2:
        return None
    try:
        flags = data[0]
        offset = 1

        if flags & 0x01:  # uint16 heart rate
            if len(data) < offset + 2:
                return None
            bpm = data[offset] | (data[offset + 1] << 8)
            offset += 2
        else:
            bpm = data[offset]
            offset += 1

        if flags & 0x08:  # energy expended present; skip it
            offset += 2

        rr_s = []
        if flags & 0x10:  # RR intervals present
            while offset + 1 < len(data):
                raw = data[offset] | (data[offset + 1] << 8)
                rr_s.append(raw / 1024.0)
                offset += 2

        if bpm <= 0 or bpm > 250:
            return None
        return {"bpm": bpm, "rr_s": rr_s}
    except (IndexError, TypeError):
        return None


def rmssd_ms(rr_seconds):
    """rMSSD in milliseconds over a list of RR intervals in seconds.

    The standard short-window HRV statistic: root mean square of successive
    differences. Needs at least two intervals; returns None otherwise. This is
    a live-session estimate from broadcast RR data — related to, but not the
    same pipeline as, WHOOP's own overnight HRV score.
    """
    if not rr_seconds or len(rr_seconds) < 2:
        return None
    diffs = [
        (rr_seconds[i + 1] - rr_seconds[i]) * 1000.0
        for i in range(len(rr_seconds) - 1)
    ]
    return (sum(d * d for d in diffs) / len(diffs)) ** 0.5


# --- The BLE shell (Pythonista-only) --------------------------------------------


class HeartRateMonitor:
    """Connects to a broadcasting WHOOP and keeps the latest reading available.

    Usage:
        monitor = HeartRateMonitor()
        if monitor.start(timeout=10):   # scans, connects, subscribes
            ...
            bpm = monitor.current_bpm()  # None until the first notification
        monitor.stop()

    All cb callbacks arrive on Pythonista's Bluetooth thread; state is plain
    attribute assignment, which is atomic enough for a reader that tolerates
    a stale-by-one value.
    """

    def __init__(self, name_contains=DEVICE_NAME_CONTAINS):
        self.name_contains = name_contains.lower()
        self.peripheral = None
        self.connected = False
        self.subscribed = False
        self.latest = None          # (epoch_seconds, bpm)
        self.rr_window = []         # rolling RR intervals for live HRV
        self.rr_window_max = 120    # ~2 minutes of beats at rest
        self.samples = 0

    # -- cb delegate callbacks --

    def did_discover_peripheral(self, p):
        if self.peripheral is not None:
            return
        name = (p.name or "").lower()
        if self.name_contains in name:
            self.peripheral = p
            import cb

            cb.connect_peripheral(p)

    def did_connect_peripheral(self, p):
        self.connected = True
        p.discover_services()

    def did_fail_to_connect_peripheral(self, p, error):
        self.peripheral = None
        self.connected = False

    def did_disconnect_peripheral(self, p, error):
        self.connected = False
        self.subscribed = False

    def did_discover_services(self, p, error):
        for service in p.services:
            if service.uuid.upper().endswith(HR_SERVICE_UUID):
                p.discover_characteristics(service)

    def did_discover_characteristics(self, service, error):
        for ch in service.characteristics:
            if ch.uuid.upper().endswith(HR_MEASUREMENT_UUID):
                self.peripheral.set_notify_value(ch, True)
                self.subscribed = True

    def did_update_value(self, ch, error):
        if error:
            return
        parsed = parse_hr_measurement(ch.value)
        if not parsed:
            return
        self.latest = (time.time(), parsed["bpm"])
        self.samples += 1
        if parsed["rr_s"]:
            self.rr_window.extend(parsed["rr_s"])
            if len(self.rr_window) > self.rr_window_max:
                del self.rr_window[: len(self.rr_window) - self.rr_window_max]

    # -- public API --

    def start(self, timeout=12):
        """Scan, connect and subscribe. True on success within the timeout."""
        try:
            import cb
        except ImportError:
            return False

        cb.set_central_delegate(self)
        cb.scan_for_peripherals()
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.subscribed:
                cb.stop_scan()
                return True
            time.sleep(0.2)
        cb.stop_scan()
        if not self.subscribed:
            self.stop()
        return self.subscribed

    def stop(self):
        try:
            import cb

            cb.reset()
        except Exception:
            pass
        self.peripheral = None
        self.connected = False
        self.subscribed = False

    def current_bpm(self, max_age_s=10.0):
        """The latest heart rate, or None if there is no fresh reading.

        Staleness matters: a dropped connection must read as "no data", not as
        a frozen number silently attached to every later swing.
        """
        if not self.latest:
            return None
        at, bpm = self.latest
        if time.time() - at > max_age_s:
            return None
        return bpm

    def live_hrv_ms(self):
        """rMSSD over the rolling RR window, or None without RR data.

        WHOOP's broadcast includes RR intervals on some firmware; when absent
        this simply stays None rather than inventing a number.
        """
        return rmssd_ms(list(self.rr_window))
