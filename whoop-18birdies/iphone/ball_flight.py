"""Animated ball flight for a logged shot, drawn on the phone.

Reads the swings recorded by swing_logger.py, then animates a ball flying the
distance you actually hit it.

WHAT IS MEASURED AND WHAT IS ASSUMED
------------------------------------
Measured   the carry distance, from GPS between consecutive swings, and the
           swing's peak acceleration.
Assumed    launch angle and backspin, which set the SHAPE of the arc. A phone
           strapped to your arm cannot measure either, so the height and
           steepness are a plausible driver flight, not your flight.

So: the ball lands where yours landed. How it got there is an illustration.
"""

import json
import os

import ui

from shot_model import metres_to_yards, trajectory_for_distance

LOG_PATH = os.path.expanduser("~/Documents/swings.json")

LAUNCH_DEG = 13.0
SPIN_RPM = 2700.0

SKY = (0.53, 0.75, 0.92)
GROUND = (0.35, 0.62, 0.30)
TRACE = (1.00, 1.00, 1.00)
BALL = (1.00, 1.00, 1.00)
TEXT = (0.10, 0.15, 0.10)

FLIGHT_SECONDS = 2.5
GROUND_FRACTION = 0.18   # share of the view height given to the ground strip


def load_shots():
    """Every logged swing that has a measured distance, longest first."""
    try:
        with open(LOG_PATH) as handle:
            data = json.load(handle)
    except (IOError, ValueError):
        return []
    shots = [s for s in data.get("swings", []) if s.get("distance_yd")]
    return sorted(shots, key=lambda s: s["distance_yd"], reverse=True)


class BallFlightView(ui.View):
    def __init__(self, distance_yd, peak_g=None, **kwargs):
        super().__init__(**kwargs)
        self.background_color = SKY
        self.distance_yd = distance_yd
        self.peak_g = peak_g

        path, speed = trajectory_for_distance(distance_yd, LAUNCH_DEG, SPIN_RPM)
        self.path = path or [(0.0, 0.0)]
        self.speed_mph = speed * 2.23694 if speed else None
        self.apex_yd = metres_to_yards(max(y for _, y in self.path))

        self.progress = 0.0
        self._running = True
        ui.delay(self.tick, 1 / 60.0)

    def tick(self):
        if not self._running:
            return
        self.progress = min(1.0, self.progress + (1 / 60.0) / FLIGHT_SECONDS)
        self.set_needs_display()
        if self.progress < 1.0:
            ui.delay(self.tick, 1 / 60.0)

    def will_close(self):
        # Stop the timer, or it keeps firing against a dead view.
        self._running = False

    def replay(self):
        self.progress = 0.0
        if self._running:
            ui.delay(self.tick, 1 / 60.0)

    def touch_began(self, touch):
        if self.progress >= 1.0:
            self.replay()

    # --- drawing -------------------------------------------------------------

    def _to_screen(self, x_m, y_m, plot_w, plot_h, ground_y, scale):
        """World metres -> screen points, with y growing upward on screen."""
        return 20 + x_m * scale, ground_y - y_m * scale

    def draw(self):
        w, h = self.width, self.height
        ground_y = h * (1 - GROUND_FRACTION)

        ui.set_color(GROUND)
        ui.Path.rect(0, ground_y, w, h - ground_y).fill()

        range_m = max(1.0, self.path[-1][0])
        apex_m = max(1e-6, max(y for _, y in self.path))
        plot_w = w - 40
        plot_h = ground_y - 40
        # One scale for both axes keeps the arc's true proportions.
        scale = min(plot_w / range_m, plot_h / apex_m)

        shown = max(2, int(len(self.path) * self.progress))
        visible = self.path[:shown]

        trace = ui.Path()
        first = True
        for x_m, y_m in visible:
            px, py = self._to_screen(x_m, y_m, plot_w, plot_h, ground_y, scale)
            if first:
                trace.move_to(px, py)
                first = False
            else:
                trace.line_to(px, py)
        trace.line_width = 2
        ui.set_color(TRACE)
        trace.stroke()

        bx, by = self._to_screen(
            visible[-1][0], visible[-1][1], plot_w, plot_h, ground_y, scale
        )
        ui.set_color(BALL)
        ui.Path.oval(bx - 5, by - 5, 10, 10).fill()

        lines = ["{:.0f} yd carry".format(self.distance_yd)]
        if self.peak_g is not None:
            lines.append("swing peak {:.1f} g".format(self.peak_g))
        if self.speed_mph:
            lines.append(
                "~{:.0f} mph ball speed, {:.0f} yd apex  (assumed {:.0f}° / {:.0f} rpm)".format(
                    self.speed_mph, self.apex_yd, LAUNCH_DEG, SPIN_RPM
                )
            )
        if self.progress >= 1.0:
            lines.append("tap to replay")

        for i, line in enumerate(lines):
            ui.draw_string(
                line,
                rect=(16, 14 + i * 20, w - 32, 20),
                font=("<system>", 14 if i else 20),
                color=TEXT,
            )


def main():
    shots = load_shots()
    if not shots:
        print("No shots with a measured distance in {}.".format(LOG_PATH))
        print("Run swing_logger.py for a round first — distance needs GPS fixes")
        print("on two consecutive swings.")
        return

    best = shots[0]
    print("Animating your longest logged shot: {:.0f} yd".format(best["distance_yd"]))
    if len(shots) > 1:
        print("({} measured shots on file)".format(len(shots)))

    view = BallFlightView(
        best["distance_yd"], best.get("peak_g"), frame=(0, 0, 420, 700)
    )
    view.name = "Ball Flight"
    view.present("fullscreen")


if __name__ == "__main__":
    main()
