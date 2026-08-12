"""Tests for club_model — inferring club bands and gapping from carries."""

import unittest

from club_model import analyze_clubs, club_gaps, cluster_distances


class TestClustering(unittest.TestCase):
    def test_separates_three_clubs(self):
        # Three tight bands around 250, 180, 140 with a clean gap between.
        dists = [248, 251, 253, 178, 181, 183, 138, 140, 142]
        bands = cluster_distances(dists)
        self.assertEqual(len(bands), 3)
        self.assertEqual([b["count"] for b in bands], [3, 3, 3])
        # Longest first.
        self.assertAlmostEqual(bands[0]["mean_yd"], 250.7, delta=0.5)
        self.assertAlmostEqual(bands[2]["mean_yd"], 140.0, delta=0.5)

    def test_merges_within_threshold(self):
        # Evenly 5 yd apart, under the 10 yd default -> one continuous band.
        dists = [100, 105, 110, 115, 120]
        bands = cluster_distances(dists)
        self.assertEqual(len(bands), 1)
        self.assertEqual(bands[0]["count"], 5)

    def test_threshold_controls_splitting(self):
        dists = [100, 112, 124]  # 12 yd gaps
        self.assertEqual(len(cluster_distances(dists, gap_threshold=10)), 3)
        self.assertEqual(len(cluster_distances(dists, gap_threshold=15)), 1)

    def test_ignores_none_and_negative(self):
        bands = cluster_distances([200, None, -5, 202])
        self.assertEqual(len(bands), 1)
        self.assertEqual(bands[0]["count"], 2)

    def test_empty(self):
        self.assertEqual(cluster_distances([]), [])
        self.assertEqual(cluster_distances([None, None]), [])

    def test_single_shot(self):
        bands = cluster_distances([175])
        self.assertEqual(len(bands), 1)
        self.assertEqual(bands[0]["spread_yd"], 0.0)


class TestGaps(unittest.TestCase):
    def test_gaps_between_adjacent_bands(self):
        bands = cluster_distances([250, 180, 140])
        gaps = club_gaps(bands)
        self.assertEqual(len(gaps), 2)
        self.assertAlmostEqual(gaps[0]["gap_yd"], 70.0, delta=0.1)
        self.assertAlmostEqual(gaps[1]["gap_yd"], 40.0, delta=0.1)

    def test_no_gaps_for_single_band(self):
        self.assertEqual(club_gaps(cluster_distances([200, 202])), [])


class TestAnalyze(unittest.TestCase):
    def test_flags_a_large_gap(self):
        # 250 then 140: a 110 yd gap, far past the missing-club threshold.
        report = analyze_clubs([248, 252, 138, 142])
        self.assertTrue(any("gap" in f.lower() for f in report["flags"]))

    def test_flags_a_wide_band(self):
        # One club spanning 200-225 across several shots is inconsistent.
        report = analyze_clubs([200, 208, 215, 220, 225])
        self.assertTrue(any("inconsistent" in f.lower() for f in report["flags"]))

    def test_clean_bag_has_no_flags(self):
        # Well-gapped, tight bands: nothing to flag.
        dists = [250, 252, 232, 234, 214, 216, 196, 198]
        report = analyze_clubs(dists)
        self.assertEqual(report["flags"], [])
        self.assertEqual(len(report["bands"]), 4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
