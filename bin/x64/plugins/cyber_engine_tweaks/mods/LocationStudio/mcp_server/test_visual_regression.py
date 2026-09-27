#!/usr/bin/env python3
"""Filesystem-only image comparison checks; does not require CET or Hyprland."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from visual_regression import compare_pngs, read_png, write_rgba_png


class PngDiffTests(unittest.TestCase):
    def test_equal_and_changed_images(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            a, b, diff = root / "a.png", root / "b.png", root / "diff.png"
            base = [(10, 20, 30, 255), (100, 100, 100, 255)]
            changed = [(10, 20, 30, 255), (255, 0, 0, 255)]
            write_rgba_png(a, 2, 1, base)
            write_rgba_png(b, 2, 1, changed)
            self.assertEqual(read_png(a), (2, 1, base))
            metrics = compare_pngs(a, b, diff, pixel_threshold=24)
            self.assertTrue(metrics["compatible"])
            self.assertEqual(metrics["changed_pixels"], 1)
            self.assertEqual(metrics["changed_fraction"], 0.5)
            self.assertTrue(diff.is_file())
            self.assertEqual(read_png(diff)[:2], (2, 1))

    def test_dimension_mismatch_is_not_silently_compared(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            a, b = root / "a.png", root / "b.png"
            write_rgba_png(a, 1, 1, [(0, 0, 0, 255)])
            write_rgba_png(b, 2, 1, [(0, 0, 0, 255)] * 2)
            metrics = compare_pngs(a, b, root / "diff.png")
            self.assertFalse(metrics["compatible"])
            self.assertEqual(metrics["baseline_size"], [1, 1])
            self.assertEqual(metrics["current_size"], [2, 1])


if __name__ == "__main__":
    unittest.main()
