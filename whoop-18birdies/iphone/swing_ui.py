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
from shot_model import shot_distances
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
        """Create the subviews. Positioning happens in layout(), not here.

        A ui.View is 100x100 until it is presented, so reading self.width in
        __init__ returns 100 — which put STOP & SAVE at y = 100 - 120 = -20,
        off the top of the screen, with no way to end a session but killing the
        script. Pythonista calls layout() once the view has a real size and again
        on every rotation, so that is where geometry belongs.
        """
        title = "RANGE" if not self.use_gps else "ROUND"
        self.title = _label(self, (0, 0, 10, 10), 15, DIM, bold=True)
        self.title.text = "SWING LOGGER · {}".format(title)

        # The hero readout: last swing force, then tempo under it.
        self.big_g = _label(self, (0, 0, 10, 10), 76, INK, bold=True)
        self.big_g.text = "—"
        self.big_tempo = _label(self, (0, 0, 10, 10), 30, ACCENT, bold=True)
        self.big_tempo.text = "waiting for a swing"

        # Two stat tiles: swing count and live HR.
        self.count_panel = self._tile("SWINGS", "count_lab")
        self.hr_panel = self._tile("WHOOP HR", "hr_lab")

        self.session = _label(self, (0, 0, 10, 10), 16, DIM)
        self.session.text = "session tempo —"

        self.status = _label(self, (0, 0, 10, 10), 13, DIM)
        self.status.text = "starting…"

        self.stop_button = ui.Button(frame=(0, 0, 10, 10))
        self.stop_button.title = "STOP & SAVE"
        self.stop_button.font = ("<system-bold>", 18)
        self.stop_button.background_color = ACCENT
        self.stop_button.tint_color = BG
        self.stop_button.corner_radius = 27
        self.stop_button.action = self._on_stop
        self.add_subview(self.stop_button)

    def layout(self):
        """Position everything against the real size.

        Called by Pythonista once the view is presented and again on every size
        change, which is the only time `self.width` means anything.

        Everything is clamped to the view. The content stack has a natural
        height and is compressed to fit when there is less room — a phone in
        landscape is barely 390 points tall, and an un-clamped layout puts the
        one control that ends a session below the bottom edge.
        """
        w = max(1.0, float(self.width or 400))
        h = max(1.0, float(self.height or 720))
        margin = 16.0
        button_h = 54.0

        # Reserve the bottom for STOP & SAVE, then fit the stack in the rest.
        content_h = max(1.0, h - (button_h + 2 * margin))
        scale = min(1.0, content_h / 440.0)   # 440 = the stack's natural height

        def y(value):
            return value * scale

        def height(value):
            return max(1.0, value * scale)

        inner = max(1.0, w - 2 * margin)

        self.title.frame = (0, y(40), w, height(24))
        self.big_g.frame = (0, y(90), w, height(90))
        self.big_tempo.frame = (0, y(182), w, height(40))

        tile_w = max(1.0, (w - 60) / 2) if w > 80 else max(1.0, w / 2 - 2)
        tile_h = height(104)
        tile_x2 = w - margin - tile_w if w > 80 else tile_w + 2
        self.count_panel.frame = (margin, y(250), tile_w, tile_h)
        self.hr_panel.frame = (tile_x2, y(250), tile_w, tile_h)
        for panel, attr in ((self.count_panel, "count_lab"), (self.hr_panel, "hr_lab")):
            panel.subviews[0].frame = (0, tile_h * 0.115, tile_w, tile_h * 0.155)
            getattr(self, attr).frame = (0, tile_h * 0.33, tile_w, tile_h * 0.54)

        self.session.frame = (margin, y(372), inner, height(26))
        self.status.frame = (margin, y(404), inner, height(22))

        # Anchored to the bottom, and clamped so it can never leave the view —
        # on a short one it simply sits as low as it fits.
        button_w = min(200.0, inner)
        self.stop_button.frame = (
            max(0.0, (w - button_w) / 2),
            max(0.0, min(h - button_h - margin, h - 120.0)),
            button_w,
            button_h,
        )

    def _tile(self, caption, attr):
        panel = ui.View(frame=(0, 0, 10, 10))
        panel.background_color = PANEL
        panel.corner_radius = 14
        self.add_subview(panel)
        _label(panel, (0, 0, 10, 10), 12, DIM, bold=True).text = caption
        val = _label(panel, (0, 0, 10, 10), 46, INK, bold=True)
        val.text = "—"
        setattr(self, attr, val)
        return panel

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
            # Measure the shots. Without this the dashboard saves a GPS round
            # with a location on every swing and a distance on none of them —
            # the headline number of a round, silently absent. The console
            # logger has always done this; the dashboard did not.
            shot_distances(self.swings)
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
