#!/usr/bin/env python3
"""Sanity-check sidecar generate-project.py output."""

import subprocess
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


class GenerateProjectTest(unittest.TestCase):
    def test_regenerates_cleanly(self):
        subprocess.run(["python3", "generate-project.py"], cwd=HERE, check=True)
        pbx = (HERE / "WhoopSwingSidecar.xcodeproj" / "project.pbxproj").read_text()
        self.assertIn("WhoopSwingSidecar", pbx)
        self.assertIn("WhoopBLEManager.swift", pbx)
        self.assertIn("WhoopFraming.swift", pbx)
        self.assertEqual(pbx.count("{"), pbx.count("}"))


if __name__ == "__main__":
    unittest.main()
