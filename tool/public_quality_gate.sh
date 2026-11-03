#!/usr/bin/env bash
# The complete public source gate. README.md, CONTRIBUTING.md, the public
# quality workflow, and the release preflight all run this one script so the
# documented quickstart cannot drift from what CI proves.
#
# It needs no Firebase project, cloud account, or credential: the web build at
# the end compiles the app against the placeholder options in
# lib/config/app_config.dart.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

flutter_packages=(
  packages/ii_ffmpeg_universal
  packages/ii_flutter_video_editor
  packages/ii_os_design_system
  packages/ii_interactive_sessions_flutter
)
flutter_examples=(
  packages/ii_ffmpeg_universal/example
  packages/ii_flutter_video_editor/example
  packages/ii_os_design_system/example
)
dart_packages=(
  packages/ii_interactive_sessions
  packages/ii_ui_mcp
)

flutter pub get --enforce-lockfile
for package in "${flutter_packages[@]}" "${flutter_examples[@]}"; do
  (cd "$package" && flutter pub get --enforce-lockfile)
done
for package in "${dart_packages[@]}" functions; do
  (cd "$package" && dart pub get --enforce-lockfile)
done

flutter analyze
# Goldens are rendered on macOS/arm64 and differ on other hosts; run them
# locally with `flutter test --tags golden` before changing UI.
flutter test --exclude-tags golden
dart run tool/audit_frontend.dart --ci
dart run tool/audit_polling_cost.dart

for package in "${flutter_packages[@]}"; do
  (
    cd "$package"
    flutter analyze
    II_FFMPEG_ALLOW_AMBIENT_TEST_ENGINE=true flutter test
  )
done
for package in "${dart_packages[@]}"; do
  (cd "$package" && dart analyze && dart test)
done
(
  cd functions
  dart format --output=none --set-exit-if-changed bin lib test
  dart analyze
  dart test
)

flutter build web --release
echo "PASS: ii-os public quality gate"
