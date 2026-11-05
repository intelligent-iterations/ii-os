#!/usr/bin/env bash
# Hermetic tests for the mobile release and FFmpeg engine tooling. They need no
# network, signing identity, store account, cloud project, or engine build.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

tool/workflow_source_identity_test.sh
tool/ffmpeg_engine_pins_test.sh
tool/android_release_settings_test.sh
tool/upload_android_internal_contract.sh
(
  cd tool
  python3 -m unittest -q \
    workflow_source_identity_test \
    android_version_code_test \
    stage_pinned_android_engine_test \
    verify_android_aab_engine_test
)
(
  cd packages/ii_ffmpeg_universal/tool
  python3 -m unittest -q package_security_evidence_test
)
printf 'release tooling tests: ok\n'
