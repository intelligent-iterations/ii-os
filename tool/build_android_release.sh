#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$repo_root/tool/workflow_source_identity.sh"
source "$repo_root/tool/ffmpeg_engine_pins.sh"

fail() {
  echo "Android release build refused: $*" >&2
  exit 1
}

require_exact() {
  local name=$1
  local expected=$2
  local actual=${3:-}
  if [[ "$actual" != "$expected" ]]; then
    echo "$name mismatch: expected '$expected', got '${actual:-<unset>}'" >&2
    exit 1
  fi
}

# Every operator setting is checked by name before any build work. The engine
# location, evidence directory, and Firebase project belong to the operator;
# none has a built-in default.
for name in \
  II_OS_ANDROID_BUILD_NAME \
  II_OS_ANDROID_BUILD_NUMBER \
  II_OS_WEB_ORIGIN \
  II_OS_FIREBASE_API_KEY \
  II_OS_FIREBASE_APP_ID \
  II_OS_FIREBASE_MESSAGING_SENDER_ID \
  II_OS_FIREBASE_PROJECT_ID \
  II_OS_FIREBASE_AUTH_DOMAIN \
  II_OS_GOOGLE_ANDROID_SERVER_CLIENT_ID \
  FLUTTER_HOME \
  II_OS_FIREBASE_EXPECTED_PROJECT_ID \
  II_FFMPEG_ANDROID_ENGINE_ROOT \
  II_OS_RELEASE_EVIDENCE_DIR; do
  if [[ -z "${!name:-}" ]]; then
    echo "$name is required" >&2
    exit 1
  fi
done
artifact_root="$II_OS_RELEASE_EVIDENCE_DIR"
[[ "$artifact_root" == /* && -d "$artifact_root" && ! -L "$artifact_root" ]] ||
  fail 'II_OS_RELEASE_EVIDENCE_DIR must be an existing absolute directory'
engine_root="$II_FFMPEG_ANDROID_ENGINE_ROOT"
[[ "$engine_root" == /* ]] ||
  fail 'II_FFMPEG_ANDROID_ENGINE_ROOT must be an absolute path'
cd "$repo_root"

if [[ "${II_OS_ANDROID_VALIDATION_ONLY:-false}" != true ]]; then
  expected_repository="$(ii_os_workflow_repository)"
  source_sha="$(ii_os_source_sha)"
  require_exact "GITHUB_REPOSITORY" "$expected_repository" "${GITHUB_REPOSITORY:-}"
  require_exact "II_OS_SOURCE_SHA" "$source_sha" "$(git rev-parse HEAD)"
fi

python3 tool/android_version_code.py validate \
  "$II_OS_ANDROID_BUILD_NUMBER" >/dev/null
II_OS_WEB_ORIGIN="${II_OS_WEB_ORIGIN%/}"
II_OS_CONTROL_API_BASE_URL="${II_OS_CONTROL_API_BASE_URL:-$II_OS_WEB_ORIGIN/api}"
[[ "$II_OS_CONTROL_API_BASE_URL" == https://*/api ]]
[[ "$II_OS_FIREBASE_PROJECT_ID" == "$II_OS_FIREBASE_EXPECTED_PROJECT_ID" ]] ||
  fail 'II_OS_FIREBASE_PROJECT_ID does not match II_OS_FIREBASE_EXPECTED_PROJECT_ID'
[[ -f android/key.properties ]]
[[ -f android/app/google-services.json ]]
# The engine was built from this repository's embedded package; its reviewed
# source revision and AAR digest come only from the committed pins file.
ffmpeg_revision="$(ii_os_engine_pin "$repo_root" engine_source_revision)"
engine_aar_sha="$(ii_os_engine_pin "$repo_root" android_aar_sha256)"

flutter_root="$FLUTTER_HOME"
flutter_version='3.44.1'
flutter_revision='924134a44c189315be2148659913dda1671cbe99'
test "$(git -C "$flutter_root" rev-parse HEAD)" = "$flutter_revision"
if ! git -C "$flutter_root" tag --points-at HEAD | grep -Fxq "$flutter_version"; then
  git -C "$flutter_root" tag "$flutter_version" HEAD
  rm -f "$flutter_root/bin/cache/flutter.version.json"
fi
test "$(flutter --version --machine | jq -r '.frameworkVersion')" = "$flutter_version"

ffmpeg_source="$repo_root/packages/ii_ffmpeg_universal"
release_state="${II_OS_ANDROID_RELEASE_STATE:-}"
[[ -d "$ffmpeg_source" && ! -L "$ffmpeg_source" ]] ||
  fail 'the embedded FFmpeg package is missing'
[[ "$(git -C "$ffmpeg_source" rev-parse --show-toplevel)" == "$repo_root" ]]
[[ "$release_state" == "$RUNNER_TEMP"/* && -d "$release_state" && \
  ! -L "$release_state" ]]
expected_owner="ii-os-android-release:${GITHUB_RUN_ID:?}:${GITHUB_RUN_ATTEMPT:?}"
[[ -f "$release_state/.ii-disposable-owner" && \
  ! -L "$release_state/.ii-disposable-owner" ]]
[[ "$(<"$release_state/.ii-disposable-owner")" == "$expected_owner" ]]

engine_artifacts="$engine_root/artifacts"
engine_aar="$engine_artifacts/ii-ffmpeg-mobile-android.aar"
engine_binding="$release_state/android-baked-engine-binding.json"
python3 tool/stage_pinned_android_engine.py \
  --engine-root "$engine_root" \
  --source "$ffmpeg_source" \
  --source-sha "$ffmpeg_revision" \
  --expected-aar-sha256 "$engine_aar_sha" \
  --output "$engine_binding"
export II_FFMPEG_ANDROID_AAR="$engine_aar"
export II_FFMPEG_ANDROID_AAR_SHA256="$engine_aar_sha"
export II_FFMPEG_REQUIRE_RELEASE_ENGINE=true

flutter pub get --enforce-lockfile

flutter build appbundle \
  --release \
  --build-name "$II_OS_ANDROID_BUILD_NAME" \
  --build-number "$II_OS_ANDROID_BUILD_NUMBER" \
  --dart-define "II_OS_CONTROL_API_BASE_URL=$II_OS_CONTROL_API_BASE_URL" \
  --dart-define "II_OS_FIREBASE_API_KEY=$II_OS_FIREBASE_API_KEY" \
  --dart-define "II_OS_FIREBASE_APP_ID=$II_OS_FIREBASE_APP_ID" \
  --dart-define "II_OS_FIREBASE_MESSAGING_SENDER_ID=$II_OS_FIREBASE_MESSAGING_SENDER_ID" \
  --dart-define "II_OS_FIREBASE_PROJECT_ID=$II_OS_FIREBASE_PROJECT_ID" \
  --dart-define "II_OS_FIREBASE_AUTH_DOMAIN=$II_OS_FIREBASE_AUTH_DOMAIN" \
  --dart-define "II_OS_GOOGLE_ANDROID_SERVER_CLIENT_ID=$II_OS_GOOGLE_ANDROID_SERVER_CLIENT_ID" \
  --dart-define "II_OS_SONG_RENDER_PROFILES_JSON=${II_OS_SONG_RENDER_PROFILES_JSON:-}"

aab="$repo_root/build/app/outputs/bundle/release/app-release.aab"
[[ -s "$aab" ]]
jarsigner -verify "$aab" >/dev/null
sha256sum "$aab" | tee "$aab.sha256"
aab_binding="$release_state/android-aab-engine-binding.json"
python3 tool/verify_android_aab_engine.py \
  --aab "$aab" \
  --aar "$engine_aar" \
  --output "$aab_binding"

[[ "$artifact_root" == /* && -d "$artifact_root" && ! -L "$artifact_root" ]]
artifact_dir="$artifact_root/ii-os/android"
install -d -m 0700 "$artifact_dir"
artifact="$artifact_dir/ii-os-${II_OS_ANDROID_BUILD_NAME}+${II_OS_ANDROID_BUILD_NUMBER}.aab"
[[ ! -e "$artifact" && ! -e "$artifact.sha256" ]]
install -m 0644 "$aab" "$artifact"
sha256sum "$artifact" > "$artifact.sha256"
engine_evidence="$artifact_dir/ffmpeg-engine"
[[ ! -e "$engine_evidence" ]]
install -d -m 0700 "$engine_evidence"
for evidence in build-attestation.json source-ledger.json \
    THIRD_PARTY_NOTICES.txt verification.json ii-ffmpeg-mobile-android.aar; do
  install -m 0600 "$engine_artifacts/$evidence" "$engine_evidence/$evidence"
done
install -m 0600 "$engine_binding" \
  "$engine_evidence/android-baked-engine-binding.json"
install -m 0600 "$aab_binding" \
  "$engine_evidence/android-aab-engine-binding.json"

{
  printf 'ANDROID_AAB_PATH=%s\n' "$aab"
  printf 'II_OS_ANDROID_SHARED_AAB_PATH=%s\n' "$artifact"
  printf 'II_OS_FFMPEG_ANDROID_EVIDENCE_PATH=%s\n' "$engine_evidence"
} >> "$GITHUB_ENV"
