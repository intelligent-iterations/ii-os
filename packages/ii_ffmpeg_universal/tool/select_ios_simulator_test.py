import importlib.util
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "select_ios_simulator", Path(__file__).with_name("select_ios_simulator.py")
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SelectIosSimulatorTest(unittest.TestCase):
    def test_selects_newest_runtime_and_compatible_modern_iphone(self):
        runtimes = [
            {
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
                "name": "iOS 17.5",
                "version": "17.5",
                "isAvailable": True,
            },
            {
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
                "name": "iOS 18.5",
                "version": "18.5",
                "isAvailable": True,
            },
        ]
        devices = [
            {
                "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                "name": "iPhone 16 Pro",
                "productFamily": "iPhone",
                "minRuntimeVersionString": "18.0.0",
                "maxRuntimeVersionString": "65535.255.255",
            },
            {
                "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-5",
                "name": "iPhone 5",
                "productFamily": "iPhone",
                "minRuntimeVersionString": "6.0.0",
                "maxRuntimeVersionString": "10.3.99",
            },
        ]

        selected = MODULE.select(runtimes, devices)

        self.assertEqual(
            selected["runtime_identifier"],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
        )
        self.assertEqual(selected["device_type_name"], "iPhone 16 Pro")

    def test_rejects_inventory_without_a_compatible_device(self):
        runtimes = [
            {
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
                "name": "iOS 18.5",
                "version": "18.5",
                "isAvailable": True,
            }
        ]
        devices = [
            {
                "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-5",
                "name": "iPhone 5",
                "maxRuntimeVersionString": "10.3.99",
            }
        ]

        with self.assertRaisesRegex(MODULE.SelectionError, "no available iOS runtime"):
            MODULE.select(runtimes, devices)

    def test_falls_back_to_an_older_runtime_with_a_compatible_device(self):
        runtimes = [
            {
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
                "name": "iOS 17.5",
                "version": "17.5",
                "isAvailable": True,
            },
            {
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
                "name": "iOS 18.5",
                "version": "18.5",
                "isAvailable": True,
            },
        ]
        devices = [
            {
                "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-15",
                "name": "iPhone 15",
                "productFamily": "iPhone",
                "minRuntimeVersionString": "17.0.0",
                "maxRuntimeVersionString": "17.99.99",
            }
        ]

        selected = MODULE.select(runtimes, devices)

        self.assertEqual(selected["runtime_version"], "17.5.0")
        self.assertEqual(selected["device_type_name"], "iPhone 15")


if __name__ == "__main__":
    unittest.main()
