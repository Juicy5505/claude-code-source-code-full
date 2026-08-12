"""A live on-screen dashboard for the swing logger, for Pythonista.

Runs the same self-calibrating detection as swing_logger.py — reusing its
detection primitives, not a re-implementation — but instead of scrolling
console text it shows a big, glanceable readout: the last swing's force and
tempo, the running swing count, live WHOOP heart rate, and session tempo
consistency. The detection sound cue is kept. A Stop button ends the session
and writes the same log file swing_logger produces, so round_report.py /
analyze.py read it identically.

Run this file directly in Pythonista and pick Range or Round.

NOTE: the `ui` and `motion` calls only exist inside Pythonista, so this cannot
be executed off-device. The detection logic it drives is fully tested in
swing_metrics / shot_model; this file is the presentation shell around it.
"""

import threading
import time
from collections import deque

import console
import motion
import ui

import location  # noqa: F401  (started/stopped for round mode)
from swing_logger import (
    AUTO_THRESHOLD,
    BUFFER_SECONDS,
    LOG_PATH,
    POST_PEAK_SECONDS,
    RANGE_LOG_PATH,
    REFRACTORY_SECONDS,
    SWING_THRESHOLD_G,
    TARGET_HZ,
    WHOOP_HR,
    PacedLoop,
    autosave,
    magnitude,
    play_cue,
    read_attitude,
    resolve_swing,
)
from swing_metrics import AdaptiveThreshold, consistency, tempo_verdict

# Palette — dark, high-contrast, one green accent.
BG = "#0d1b12"
PANEL = "#13251a"
INK = "#e8f5ec"
DIM = "#6f8a78"
ACCENT = "#3ddc84"
WARN = "#f2b134"


def _label(view, frame, size, color=INK, align=ui.ALIGN_CENTER, bold=False):
    lab = ui.Label(frame=frame)
    lab.text_color = color
    lab.alignment = align
    lab.font = ("<system-bold>" if bold else "<system>", size)
    lab.number_of_lines = 1
    view.add_subview(lab)
    return lab


class SwingDashboard(ui.View):
    """Full-screen live readout. Detection runs on a background thread; the UI
    refreshes on the main thread from a shared snapshot, which is the safe way
    to touch Pythonista views from off the main thread."""

    def __init__(self, mode):
        self.mode = mode
        self.use_gps = mode == "round"
        self.log_path = LOG_PATH if self.use_gps else RANGE_LOG_PATH

        self.background_color = BG
        self.name = "Swing Logger"

        self.swings = []
        self.hr = None
        self._running = True
        self._lock = threading.Lock()
        # Snapshot the UI reads; the worker writes it under the lock.
        self._snap = {
            "count": 0,
            "last_g": None,
            "last_tempo": None,
            "last_frames": None,
            "hr": None,
            "status": "starting…",
            "rate": 0,
        }

        self._build()

    # -- layout --

    def _build(self):
        w, h = self.width or 400, self.height or 720

        title = "RANGE" if not self.use_gps else "ROUND"
        self.title = _label(self, (0, 40, w, 24), 15, DIM, bold=True)
        self.title.text = "SWING LOGGER · {}".format(title)

        # The hero readout: last swing force, then tempo under it.
        self.big_g = _label(self, (0, 90, w, 90), 76, INK, bold=True)
        self.big_g.text = "—"
        self.big_tempo = _label(self, (0, 182, w, 40), 30, ACCENT, bold=True)
        self.big_tempo.text = "waiting for a swing"

        # Two stat tiles: swing count and live HR.
        tile_w = (w - 60) / 2
        self._tile(20, 250, tile_w, "SWINGS", "count_lab")
        self._tile(40 + tile_w, 250, tile_w, "WHOOP HR", "hr_lab")

        # Session tempo line.
        self.session = _label(self, (20, 372, w - 40, 26), 16, DIM)
        self.session.text = "session tempo —"

        # Status / connection line.
        self.status = _label(self, (20, 404, w - 40, 22), 13, DIM)
        self.status.text = "starting…"

        stop = ui.Button(frame=((w - 200) / 2, h - 120, 200, 54))
        stop.title = "STOP & SAVE"
        stop.font = ("<system-bold>", 18)
        stop.background_color = ACCENT
        stop.tint_color = BG
        stop.corner_radius = 27
        stop.action = self._on_stop
        self.add_subview(stop)

    def _tile(self, x, y, tw, caption, attr):
        panel = ui.View(frame=(x, y, tw, 104))
        panel.background_color = PANEL
        panel.corner_radius = 14
        self.add_subview(panel)
        _label(panel, (0, 12, tw, 16), 12, DIM, bold=True).text = caption
        val = _label(panel, (0, 34, tw, 56), 46, INK, bold=True)
        val.text = "—"
        setattr(self, attr, val)

    # -- lifecycle --

    def did_load(self):
        pass

    def will_close(self):
        self._running = False

    def present_and_run(self):
        self.present("fullscreen")
        self._start_hr()
        motion.start_updates()
        if self.use_gps:
            location.start_updates()
        threading.Thread(target=self._worker, daemon=True).start()
        self._schedule_refresh()

    def _start_hr(self):
        if not WHOOP_HR:
            return
        try:
            from hr_monitor import HeartRateMonitor

            self._set_status("scanning for WHOOP…")
            cand = HeartRateMonitor()
            if cand.start(timeout=12):
                self.hr = cand
                self._set_status("WHOOP connected — live HR on every swing")
            else:
                self._set_status("no WHOOP found — HR Broadcast on? Running without it")
        except Exception as exc:
            self._set_status("HR unavailable ({}) — running without it".format(exc))

    # -- worker thread: the detection loop --

    def _worker(self):
        buffer = deque(maxlen=max(16, int(BUFFER_SECONDS * TARGET_HZ)))
        detector = AdaptiveThreshold(sample_hz=TARGET_HZ) if AUTO_THRESHOLD else None
        started = time.time()
        samples = 0
        last_detection = 0.0
        trip_time = None
        pacer = PacedLoop(TARGET_HZ)

        self._set_status(
            "watching — {}".format(
                "self-calibrating" if detector else "fixed %.1f g" % SWING_THRESHOLD_G
            )
        )

        while self._running:
            now = time.time()
            mag = magnitude(motion.get_user_acceleration())
            buffer.append((now, mag, read_attitude()))
            samples += 1
            if detector:
                detector.observe(mag)

            if trip_time is None:
                tripped = detector.is_swing(mag) if detector else mag >= SWING_THRESHOLD_G
                if tripped and (now - last_detection) >= REFRACTORY_SECONDS:
                    trip_time = now
            elif now - trip_time >= POST_PEAK_SECONDS:
                swing = resolve_swing(buffer, trip_time, len(self.swings) + 1, self.use_gps)
                if swing:
                    if self.hr:
                        swing["hr_bpm"] = self.hr.current_bpm()
                    self.swings.append(swing)
                    play_cue()
                    autosave(self.log_path, self.mode, self.swings, detector, started, samples)
                    self._publish(swing, samples / max(1e-6, now - started))
                last_detection = now
                trip_time = None

            pacer.wait()

        # Session ended — stop sensors and persist a final time.
        motion.stop_updates()
        if self.use_gps:
            location.stop_updates()
        if self.hr:
            self.hr.stop()
        autosave(self.log_path, self.mode, self.swings, detector, started, samples)

    # -- shared-state plumbing --

    def _publish(self, swing, rate):
        with self._lock:
            self._snap["count"] = len(self.swings)
            self._snap["last_g"] = swing.get("peak_g")
            self._snap["last_tempo"] = swing.get("tempo_ratio")
            self._snap["last_frames"] = swing.get("tempo_frames")
            self._snap["hr"] = swing.get("hr_bpm")
            self._snap["rate"] = rate

    def _set_status(self, text):
        with self._lock:
            self._snap["status"] = text

    def _snapshot(self):
        with self._lock:
            return dict(self._snap)

    # -- main-thread refresh --

    def _schedule_refresh(self):
        if self._running:
            self._refresh()
            ui.delay(self._schedule_refresh, 0.15)

    def _refresh(self):
        s = self._snapshot()

        self.big_g.text = "{:.1f} g".format(s["last_g"]) if s["last_g"] is not None else "—"
        if s["last_tempo"]:
            frames = " · {}".format(s["last_frames"]) if s["last_frames"] else ""
            self.big_tempo.text = "{:.1f}:1{}".format(s["last_tempo"], frames)
            self.big_tempo.text_color = ACCENT
        elif s["count"]:
            self.big_tempo.text = "no tempo (pause at address)"
            self.big_tempo.text_color = WARN
        else:
            self.big_tempo.text = "waiting for a swing"
            self.big_tempo.text_color = DIM

        self.count_lab.text = str(s["count"])
        self.hr_lab.text = "{}".format(s["hr"]) if s["hr"] else "—"

        stats = consistency(self.swings, "tempo_ratio")
        if stats:
            self.session.text = "session {:.2f}:1   cv {:.2f}   {}".format(
                stats["mean"], stats["cv"], tempo_verdict(stats["mean"])
            )
        self.status.text = "{}    ~{:.0f} Hz".format(s["status"], s["rate"])

    def _on_stop(self, _sender):
        self._running = False
        # Give the worker a beat to flush its final save before the view closes.
        ui.delay(self.close, 0.4)


def main():
    choice = console.alert(
        "Swing Logger",
        "Live dashboard. Detection self-calibrates from your motion.",
        "Range (no GPS)",
        "Play a round (GPS)",
        hide_cancel_button=False,
    )
    mode = "round" if choice == 2 else "range"
    SwingDashboard(mode).present_and_run()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
