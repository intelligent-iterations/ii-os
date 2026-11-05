#!/usr/bin/env python3
"""Derive and validate monotonic Google Play version codes for ii-os."""

import argparse
import re


# Version codes live in a high generation above any code an earlier release
# path may have used, so a fresh workflow run-number sequence can never
# produce a downgrade. Google Play rejects codes above GOOGLE_PLAY_MAX.
GENERATION_BASE = 1_000_000_000
GOOGLE_PLAY_MAX = 2_100_000_000
_POSITIVE_DECIMAL = re.compile(r"[1-9][0-9]*")


def _parse_positive_decimal(value: str, label: str) -> int:
    if not _POSITIVE_DECIMAL.fullmatch(value):
        raise ValueError(f"{label} must be a positive decimal without leading zeroes")
    return int(value)


def derive(run_number: str) -> int:
    """Map the approved wrapper's monotonic run number into a new generation."""
    parsed_run_number = _parse_positive_decimal(run_number, "GitHub run number")
    version_code = GENERATION_BASE + parsed_run_number
    if version_code > GOOGLE_PLAY_MAX:
        raise ValueError(
            "Android version-code generation is exhausted; choose a new "
            "monotonic scheme before releasing"
        )
    return version_code


def validate(version_code: str) -> int:
    parsed_version_code = _parse_positive_decimal(
        version_code,
        "Android version code",
    )
    if parsed_version_code > GOOGLE_PLAY_MAX:
        raise ValueError(
            f"Android version code exceeds Google Play maximum {GOOGLE_PLAY_MAX}"
        )
    return parsed_version_code


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("derive", "validate"))
    parser.add_argument("value")
    args = parser.parse_args()

    try:
        if args.operation == "derive":
            print(f"II_OS_ANDROID_BUILD_NUMBER={derive(args.value)}")
        else:
            print(validate(args.value))
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
