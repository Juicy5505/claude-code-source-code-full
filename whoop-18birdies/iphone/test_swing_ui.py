"""Tests for the Pythonista dashboard's layout and session finalisation.

The dashboard cannot be fully exercised off-device — `motion`, `location`,
`console` and `ui` only exist inside Pythonista. But the two defects that made
it unusable were both pure logic, and both are testable with a stub `ui`:

  * every control was positioned from `self.width` in `__init__`, when a
    ui.View is still 100x100, so STOP & SAVE landed at y = -20 and there was no
    way to end a session except killing the script;
  * a GPS round was saved with a location on every swing and a distance on
    none, because the worker never called shot_distances.

Both are the kind of bug that only shows up on a course, which is the worst
possible place to find them.
"""

import sys
import types
import unittest


def install_pythonista_stubs():
    """A `ui` module just real enough to lay a view out and inspect it."""

    class Frame:
        def __init__(self, x=0, y=0, w=0, h=0):
            self.x, self.y, self.width, self.height = x, y, w, h

    class View:
        """Lazily initialised, because Pythonista's own idiom is to subclass
        ui.View and define __init__ WITHOUT calling super() — the real View is a
        native object whose attributes exist regardless. A stub that required
        super() would fail on correct code."""

        def __init__(self, frame=(0, 0, 100, 100), **kwargs):
            self._frame = tuple(frame)

        @property
        def subviews(self):
            return self.__dict__.setdefault("_subviews", [])

        @property
        def frame(self):
            return self.__dict__.setdefault("_frame", (0, 0, 100, 100))

        @frame.setter
        def frame(self, value):
            self.__dict__["_frame"] = tuple(value)

        @property
        def x(self):
            return self.frame[0]

        @property
        def y(self):
            return self.frame[1]

        @property
        def width(self):
            return self.frame[2]

        @width.setter
        def width(self, value):
            f = self.frame
            self.frame = (f[0], f[1], value, f[3])

        @property
        def height(self):
            return self.frame[3]

        @height.setter
        def height(self, value):
            f = self.frame
            self.frame = (f[0], f[1], f[2], value)

        def add_subview(self, view):
            self.subviews.append(view)

        def present(self, *args, **kwargs):
            pass

        def close(self):
            pass

    class Label(View):
        pass

    class Button(View):
        pass

    ui = types.ModuleType("ui")
    ui.View, ui.Label, ui.Button = View, Label, Button
    ui.ALIGN_CENTER = 1
    ui.delay = lambda fn, secs: None
    ui.in_background = lambda fn: fn
    sys.modules["ui"] = ui

    for name in ("console", "motion", "location", "sound", "cb"):
        module = types.ModuleType(name)
        sys.modules[name] = module
    sys.modules["console"].alert = lambda *a, **k: 1
    sys.modules["motion"].start_updates = lambda: None
    sys.modules["motion"].stop_updates = lambda: None
    sys.modules["motion"].get_user_acceleration = lambda: (0.0, 0.0, 0.0)
    sys.modules["motion"].get_attitude = lambda: (0.0, 0.0, 0.0)
    sys.modules["location"].start_updates = lambda: None
    sys.modules["location"].stop_updates = lambda: None
    sys.modules["location"].get_location = lambda: None
    return ui


UI = install_pythonista_stubs()
import swing_ui  # noqa: E402


class TestLayout(unittest.TestCase):
    """Every control must be inside the view once it has a real size."""

    def dashboard(self, width, height, mode="round"):
        board = swing_ui.SwingDashboard(mode)
        board.width = width
        board.height = height
        board.layout()
        return board

    def assert_on_screen(self, view, w, h, label):
        x, y, vw, vh = view.frame
        self.assertGreaterEqual(x, 0, "{}: x off the left edge".format(label))
        self.assertGreaterEqual(y, 0, "{}: y off the top edge".format(label))
        self.assertLessEqual(x + vw, w + 1, "{}: runs off the right".format(label))
        self.assertLessEqual(y + vh, h + 1, "{}: runs off the bottom".format(label))

    def test_stop_button_is_on_screen_on_a_phone(self):
        # THE bug: at 100x100 the button was placed at y = 100 - 120 = -20.
        board = self.dashboard(390, 844)   # iPhone 14 points
        self.assert_on_screen(board.stop_button, 390, 844, "STOP & SAVE")

    def test_stop_button_is_reachable_on_a_small_view(self):
        board = self.dashboard(320, 568)   # the smallest iPhone still supported
        self.assert_on_screen(board.stop_button, 320, 568, "STOP & SAVE")

    def test_stop_button_never_lands_at_a_negative_coordinate(self):
        # Even at the pre-presentation default, layout() must not go negative.
        board = self.dashboard(100, 100)
        self.assertGreaterEqual(board.stop_button.frame[0], 0)
        self.assertGreaterEqual(board.stop_button.frame[1], 0)

    def test_tiles_do_not_overlap_and_stay_inside_the_view(self):
        w, h = 390, 844
        board = self.dashboard(w, h)
        left = board.count_panel.frame
        right = board.hr_panel.frame
        self.assertLessEqual(left[0] + left[2], right[0] + 1, "tiles overlap")
        self.assertLessEqual(right[0] + right[2], w, "right tile runs off screen")

    def test_layout_is_idempotent(self):
        board = self.dashboard(390, 844)
        first = board.stop_button.frame
        board.layout()
        board.layout()
        self.assertEqual(first, board.stop_button.frame)

    def test_relayout_after_a_size_change_repositions(self):
        # Rotation, or the keyboard appearing.
        board = self.dashboard(390, 844)
        portrait = board.stop_button.frame
        board.width, board.height = 844, 390
        board.layout()
        self.assertNotEqual(portrait, board.stop_button.frame)
        self.assert_on_screen(board.stop_button, 844, 390, "STOP & SAVE rotated")


class TestSessionFinalisation(unittest.TestCase):
    def test_a_gps_round_measures_its_shots(self):
        """The dashboard must compute distances, as the console logger does.

        Without this a whole round saves a location on every swing and a
        distance on none — the number the round was tracked for, silently
        missing, discovered only afterwards.
        """
        import shot_model

        swings = [
            {"index": 1, "timestamp": "2026-08-17T14:00:00",
             "location": {"latitude": 32.8973, "longitude": -117.2531}},
            {"index": 2, "timestamp": "2026-08-17T14:04:00",
             "location": {"latitude": 32.8991, "longitude": -117.2531}},
        ]
        shot_model.shot_distances(swings)
        self.assertIsNotNone(swings[0].get("distance_yd"))
        self.assertGreater(swings[0]["distance_yd"], 100)

    def test_the_worker_calls_shot_distances_for_gps_rounds(self):
        # Guards against the call being dropped again: assert it is present in
        # the round-mode teardown path.
        import inspect

        source = inspect.getsource(swing_ui.SwingDashboard._worker)
        self.assertIn("shot_distances", source)
        # And that it is inside the use_gps branch, not run for range sessions
        # where standing still would produce noise rather than distances.
        gps_branch = source.split("if self.use_gps:")[-1]
        self.assertIn("shot_distances", gps_branch)


if __name__ == "__main__":
    unittest.main(verbosity=2)
