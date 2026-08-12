"""Tests for the BLE heart-rate packet parser and live HRV math.

These cover the pure-Python half of hr_monitor. The cb shell is
Pythonista-only and untestable off-device, so everything it feeds on is
proven here instead — including malformed packets, because a garbled
notification must never take a session down.
"""

import unittest

from hr_monitor import parse_hr_measurement, rmssd_ms


class TestParseHrMeasurement(unittest.TestCase):
    def test_uint8_heart_rate(self):
        # flags 0x00: HR is one byte, nothing else present.
        out = parse_hr_measurement(bytes([0x00, 72]))
        self.assertEqual(out["bpm"], 72)
        self.assertEqual(out["rr_s"], [])

    def test_uint16_heart_rate(self):
        # flags bit 0 set: HR is uint16 little-endian.
        out = parse_hr_measurement(bytes([0x01, 0x48, 0x00]))
        self.assertEqual(out["bpm"], 72)

    def test_rr_intervals_in_1024ths(self):
        # flags bit 4: one RR interval of exactly 1.0 s (1024/1024).
        out = parse_hr_measurement(bytes([0x10, 72, 0x00, 0x04]))
        self.assertEqual(out["bpm"], 72)
        self.assertEqual(out["rr_s"], [1.0])

    def test_multiple_rr_intervals(self):
        # Two RRs: 1024 -> 1.0 s and 512 -> 0.5 s.
        out = parse_hr_measurement(bytes([0x10, 60, 0x00, 0x04, 0x00, 0x02]))
        self.assertEqual(out["rr_s"], [1.0, 0.5])

    def test_energy_expended_is_skipped_not_misread(self):
        # flags 0x18: energy (2 bytes) precedes RR. If the offset math is
        # wrong, the energy bytes would be parsed as an RR interval.
        out = parse_hr_measurement(bytes([0x18, 90, 0xFF, 0xFF, 0x00, 0x04]))
        self.assertEqual(out["bpm"], 90)
        self.assertEqual(out["rr_s"], [1.0])

    def test_malformed_packets_return_none(self):
        self.assertIsNone(parse_hr_measurement(b""))
        self.assertIsNone(parse_hr_measurement(None))
        self.assertIsNone(parse_hr_measurement(bytes([0x00])))
        # flags promise uint16 HR but only one byte follows.
        self.assertIsNone(parse_hr_measurement(bytes([0x01, 0x48])))

    def test_implausible_bpm_rejected(self):
        self.assertIsNone(parse_hr_measurement(bytes([0x00, 0])))
        out = parse_hr_measurement(bytes([0x01, 0xFF, 0x01]))  # 511 bpm
        self.assertIsNone(out)

    def test_trailing_odd_byte_ignored(self):
        # An RR section with a dangling odd byte parses what is complete.
        out = parse_hr_measurement(bytes([0x10, 70, 0x00, 0x04, 0x99]))
        self.assertEqual(out["rr_s"], [1.0])


class TestRmssd(unittest.TestCase):
    def test_known_value(self):
        # diffs: +100 ms, -200 ms -> sqrt((100^2 + 200^2)/2) = sqrt(25000).
        out = rmssd_ms([1.0, 1.1, 0.9])
        self.assertAlmostEqual(out, 25000 ** 0.5, places=6)

    def test_steady_rhythm_is_zero(self):
        self.assertAlmostEqual(rmssd_ms([0.8, 0.8, 0.8, 0.8]), 0.0, places=9)

    def test_needs_two_intervals(self):
        self.assertIsNone(rmssd_ms([]))
        self.assertIsNone(rmssd_ms([1.0]))
        self.assertIsNone(rmssd_ms(None))


if __name__ == "__main__":
    unittest.main(verbosity=2)
