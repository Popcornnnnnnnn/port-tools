import importlib.util
import os
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "evaluation" / "measure_release_metrics.py"
SPEC = importlib.util.spec_from_file_location("measure_release_metrics", MODULE_PATH)
release_metrics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_metrics)


class ReleaseMetricsTests(unittest.TestCase):
    def test_physical_footprint_is_available_for_current_process(self):
        self.assertGreater(release_metrics.physical_footprint_kib(os.getpid()), 0)

    def test_process_metrics_reports_footprint_and_rss(self):
        cpu, footprint_kib, rss_kib = release_metrics.process_metrics([os.getpid()])
        self.assertGreaterEqual(cpu, 0)
        self.assertGreater(footprint_kib, 0)
        self.assertGreater(rss_kib, 0)


if __name__ == "__main__":
    unittest.main()
