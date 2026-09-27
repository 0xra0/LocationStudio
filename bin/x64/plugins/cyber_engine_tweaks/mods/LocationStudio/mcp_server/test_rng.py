import unittest

from lsbuild.rng import create


class SeededRngTests(unittest.TestCase):
    def test_same_seed_repeats_and_normalizes_zero(self):
        self.assertEqual(create(12345, 8), create(12345, 8))
        self.assertEqual(create(0, 1)["seed"], 1)
        self.assertEqual(create(-9, 0)["seed"], 9)

    def test_seed_generation_and_bounds(self):
        value = create(None, 4)
        self.assertGreaterEqual(value["seed"], 1)
        self.assertLess(value["seed"], 2147483647)
        self.assertEqual(len(value["samples"]), 4)
        with self.assertRaises(ValueError):
            create(1, 65)


if __name__ == "__main__":
    unittest.main()
