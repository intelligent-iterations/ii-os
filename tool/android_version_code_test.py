import unittest

import android_version_code


class AndroidVersionCodeTest(unittest.TestCase):
    def test_derives_new_generation_above_legacy_workflow_codes(self) -> None:
        self.assertEqual(android_version_code.derive("1"), 1_000_000_001)
        self.assertEqual(android_version_code.derive("6"), 1_000_000_006)

    def test_accepts_largest_supported_run_number(self) -> None:
        self.assertEqual(
            android_version_code.derive("1100000000"),
            2_100_000_000,
        )

    def test_rejects_invalid_or_exhausted_run_numbers(self) -> None:
        for value in ("", "0", "01", "-1", "not-a-number", "1100000001"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    android_version_code.derive(value)

    def test_validates_google_play_version_code_bounds(self) -> None:
        for value in ("1", "1000000006", "2100000000"):
            with self.subTest(value=value):
                self.assertEqual(android_version_code.validate(value), int(value))

        for value in ("", "0", "01", "-1", "not-a-number", "2100000001"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    android_version_code.validate(value)


if __name__ == "__main__":
    unittest.main()
