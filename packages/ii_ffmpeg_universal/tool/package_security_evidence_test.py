import unittest
from pathlib import Path
from unittest import mock

import package_security_evidence as evidence


class PackageSecurityEvidenceTest(unittest.TestCase):
    def test_macos_attests_unsandboxed_process_execution(self):
        with mock.patch.object(
            evidence,
            "run_checked",
            side_effect=("valid signature", "<plist><dict/></plist>"),
        ):
            result = evidence.apple_security(Path("Example.app"), "macos")

        self.assertEqual(
            result,
            {
                "codesign_verified": True,
                "app_sandbox": False,
                "execution_model": "attested-child-process",
            },
        )

    def test_macos_rejects_a_misleading_sandbox_entitlement(self):
        entitlements = (
            "<plist><dict><key>com.apple.security.app-sandbox</key>"
            "<true/></dict></plist>"
        )
        with mock.patch.object(
            evidence,
            "run_checked",
            side_effect=("valid signature", entitlements),
        ):
            with self.assertRaisesRegex(RuntimeError, "must not claim App Sandbox"):
                evidence.apple_security(Path("Example.app"), "macos")


if __name__ == "__main__":
    unittest.main()
