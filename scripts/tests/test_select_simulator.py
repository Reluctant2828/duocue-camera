import json
import subprocess
import sys
import unittest
from pathlib import Path

SELECTOR = Path(__file__).resolve().parents[1] / "select_simulator.py"


def device(name, identifier, available=True):
    return {"name": name, "udid": identifier, "isAvailable": available}


class SimulatorSelectionTests(unittest.TestCase):
    def run_selector(self, devices):
        return subprocess.run([sys.executable, str(SELECTOR)],
                              input=json.dumps({"devices": devices}),
                              text=True, capture_output=True, check=False)

    def test_prefers_ios_27_1_duo_and_never_uses_ios_26(self):
        result = self.run_selector({
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [device("iPhone 17", "old")],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-2": [device("iPhone Duo", "newer")],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone 18", "normal"), device("iPhone Duo", "target")],
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "target")

    def test_rejects_unavailable_and_too_old_simulators(self):
        result = self.run_selector({
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [device("iPhone 17", "old")],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone Duo", "offline", False)],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-2": [device("iPad Pro", "ipad")],
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No available iPhone simulator", result.stderr)

    def test_accepts_newer_sdk_when_27_1_is_unavailable(self):
        result = self.run_selector({
            "com.apple.CoreSimulator.SimRuntime.iOS-27-2": [device("iPhone Duo", "compatible")],
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "compatible")


if __name__ == "__main__":
    unittest.main()
