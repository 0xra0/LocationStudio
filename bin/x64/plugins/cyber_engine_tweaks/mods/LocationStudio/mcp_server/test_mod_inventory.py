import tempfile
import unittest
from pathlib import Path

from mod_inventory import scan_mod_installation


class ModInventoryTests(unittest.TestCase):
    def test_lists_common_mod_entries_without_claiming_compatibility(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "archive/pc/mod").mkdir(parents=True)
            (root / "archive/pc/mod/sample.archive").touch()
            (root / "r6/scripts").mkdir(parents=True)
            (root / "r6/scripts/sample.reds").touch()
            (root / "bin/x64/plugins/cyber_engine_tweaks/mods/AMM").mkdir(parents=True)
            (root / "bin/x64/plugins/red4ext/plugins/PluginA").mkdir(parents=True)
            report = scan_mod_installation(root)
            self.assertFalse(report["verified_compatibility"])
            self.assertEqual(report["locations"]["archives"]["entries"], ["sample.archive"])
            self.assertEqual(report["locations"]["redscript"]["entries"], ["sample.reds"])
            self.assertEqual(report["locations"]["cet"]["entries"], ["AMM"])
            self.assertEqual(report["locations"]["red4ext"]["entries"], ["PluginA"])

    def test_missing_installation_paths_are_reported(self):
        with tempfile.TemporaryDirectory() as temporary:
            report = scan_mod_installation(Path(temporary))
            self.assertFalse(report["locations"]["archives"]["exists"])
            self.assertEqual(report["locations"]["archives"]["count"], 0)


if __name__ == "__main__":
    unittest.main()
