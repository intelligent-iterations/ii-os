#!/usr/bin/env bash
# Android release settings fail closed by name, before any build work, and the
# Firebase project is the operator's setting rather than a built-in value.
# The scripts run from a disposable copy of the tool tree so the test can never
# overwrite a developer's signing or Firebase files.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
owner="ii-os-android-release-settings-test-$$-$RANDOM"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/$owner.XXXXXX")"
printf '%s\n' "$owner" >"$fixture/.ii-disposable-owner"

cleanup() {
  if [[ -d "$fixture" ]]; then
    [[ -f "$fixture/.ii-disposable-owner" ]]
    [[ "$(<"$fixture/.ii-disposable-owner")" == "$owner" ]]
    find "$fixture" -xdev -depth -delete
  fi
}
trap cleanup EXIT

source_root="$fixture/source"
mkdir -p "$source_root/tool" "$source_root/android/app" "$fixture/runner" \
  "$fixture/evidence"
for script in build_android_release.sh materialize_android_release.sh cleanup_android_release.sh \
    upload_android_internal.sh workflow_source_identity.sh \
    ffmpeg_engine_pins.sh android_version_code.py; do
  cp "$repo_root/tool/$script" "$source_root/tool/$script"
done

expect_refusal() {
  local reason="$1"
  shift
  if env "$@" >"$fixture/refusal.stdout" 2>"$fixture/refusal.stderr"; then
    echo "accepted a case that must refuse: $reason" >&2
    exit 1
  fi
  grep -Fq "$reason" "$fixture/refusal.stderr" || {
    echo "refused for the wrong reason (wanted: $reason)" >&2
    cat "$fixture/refusal.stderr" >&2
    exit 1
  }
}

build_settings=(
  PATH="$PATH"
  RUNNER_TEMP="$fixture/runner"
  GITHUB_RUN_ID=1
  GITHUB_RUN_ATTEMPT=1
  II_OS_ANDROID_VALIDATION_ONLY=true
  II_OS_ANDROID_BUILD_NAME=1.0.0
  II_OS_ANDROID_BUILD_NUMBER=1000000001
  II_OS_WEB_ORIGIN=https://app.example.com
  II_OS_FIREBASE_API_KEY=example-api-key
  II_OS_FIREBASE_APP_ID=example-app-id
  II_OS_FIREBASE_MESSAGING_SENDER_ID=000000000000
  II_OS_FIREBASE_PROJECT_ID=example-project
  II_OS_FIREBASE_AUTH_DOMAIN=example-project.firebaseapp.com
  II_OS_GOOGLE_ANDROID_SERVER_CLIENT_ID=example-client
  FLUTTER_HOME="$fixture/flutter"
  II_OS_FIREBASE_EXPECTED_PROJECT_ID=example-project
  II_FFMPEG_ANDROID_ENGINE_ROOT="$fixture/engine"
  II_OS_RELEASE_EVIDENCE_DIR="$fixture/evidence"
)

without() {
  local name="$1"
  local setting
  for setting in "${build_settings[@]}"; do
    [[ "$setting" == "$name="* ]] || printf '%s\0' "$setting"
  done
}

# Each operator setting is required by name; nothing falls back to a built-in
# engine location, evidence directory, or Firebase project.
for name in II_OS_FIREBASE_EXPECTED_PROJECT_ID II_FFMPEG_ANDROID_ENGINE_ROOT \
    II_OS_RELEASE_EVIDENCE_DIR II_OS_WEB_ORIGIN FLUTTER_HOME; do
  settings=()
  while IFS= read -r -d '' setting; do settings+=("$setting"); done \
    < <(without "$name")
  expect_refusal "$name is required" -i "${settings[@]}" \
    bash "$source_root/tool/build_android_release.sh"
done

# Evidence is retained only in an existing absolute directory, checked before
# the build spends any time.
expect_refusal 'II_OS_RELEASE_EVIDENCE_DIR must be an existing absolute directory' \
  -i "${build_settings[@]}" II_OS_RELEASE_EVIDENCE_DIR=relative/evidence \
  bash "$source_root/tool/build_android_release.sh"
expect_refusal 'II_FFMPEG_ANDROID_ENGINE_ROOT must be an absolute path' \
  -i "${build_settings[@]}" II_FFMPEG_ANDROID_ENGINE_ROOT=engine \
  bash "$source_root/tool/build_android_release.sh"

# The app must be built against the operator's own Firebase project.
expect_refusal \
  'II_OS_FIREBASE_PROJECT_ID does not match II_OS_FIREBASE_EXPECTED_PROJECT_ID' \
  -i "${build_settings[@]}" II_OS_FIREBASE_EXPECTED_PROJECT_ID=another-project \
  bash "$source_root/tool/build_android_release.sh"

# A non-validation build names its workflow repository; there is no default.
expect_refusal 'II_OS_WORKFLOW_REPOSITORY is required' \
  -i "${build_settings[@]}" II_OS_ANDROID_VALIDATION_ONLY=false \
  bash "$source_root/tool/build_android_release.sh"

# Signing material is validated against the operator's project and package.
materialize_settings=(
  PATH="$PATH"
  RUNNER_TEMP="$fixture/runner"
  GITHUB_ENV="$fixture/github.env"
  GITHUB_RUN_ID=7
  GITHUB_RUN_ATTEMPT=1
  II_OS_ANDROID_APPLICATION_ID=org.example.app
  II_OS_FIREBASE_EXPECTED_PROJECT_ID=example-project
  II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64=unused
  II_OS_ANDROID_KEY_PROPERTIES=unused
  II_OS_ANDROID_GOOGLE_SERVICES_JSON=unused
)
: >"$fixture/github.env"
for name in II_OS_FIREBASE_EXPECTED_PROJECT_ID II_OS_ANDROID_APPLICATION_ID; do
  settings=()
  for setting in "${materialize_settings[@]}"; do
    [[ "$setting" == "$name="* ]] || settings+=("$setting")
  done
  expect_refusal "$name is required" -i "${settings[@]}" \
    bash "$source_root/tool/materialize_android_release.sh"
done
# Refusals happen before any run-owned state or signing file is written.
[[ -z "$(find "$fixture/runner" -mindepth 1 -print -quit)" ]]
[[ ! -e "$source_root/android/key.properties" ]]
[[ ! -s "$fixture/github.env" ]]

# Developer files are never overwritten or removed by a failed/no-op run.
printf 'developer signing settings\n' > "$source_root/android/key.properties"
printf 'developer Firebase settings\n' > "$source_root/android/app/google-services.json"
env -i PATH="$PATH" bash "$source_root/tool/cleanup_android_release.sh"
grep -Fxq 'developer signing settings' "$source_root/android/key.properties"
grep -Fxq 'developer Firebase settings' "$source_root/android/app/google-services.json"
expect_refusal 'Refusing to overwrite existing Android release configuration' \
  -i "${materialize_settings[@]}" bash "$source_root/tool/materialize_android_release.sh"
grep -Fxq 'developer signing settings' "$source_root/android/key.properties"
grep -Fxq 'developer Firebase settings' "$source_root/android/app/google-services.json"
rm "$source_root/android/key.properties" "$source_root/android/app/google-services.json"

if command -v keytool >/dev/null && command -v openssl >/dev/null; then
  password="$(openssl rand -hex 16)"
  keystore="$fixture/upload.jks"
  II_OS_TEST_KEY_PASSWORD="$password" keytool -genkeypair \
    -keystore "$keystore" \
    -storepass:env II_OS_TEST_KEY_PASSWORD \
    -keypass:env II_OS_TEST_KEY_PASSWORD \
    -alias example-upload -keyalg RSA -keysize 2048 -validity 1 \
    -dname 'CN=Example upload key,O=Example,C=US' -noprompt >/dev/null 2>&1
  google_services() {
    printf '{"project_info":{"project_number":"000000000000","project_id":"%s"},' "$1"
    printf '"client":[{"client_info":{"mobilesdk_app_id":"1:000000000000:android:0000000000000000",'
    printf '"android_client_info":{"package_name":"org.example.app"}},'
    printf '"oauth_client":[{"client_id":"000000000000-example.apps.googleusercontent.com","client_type":3}],'
    printf '"api_key":[{"current_key":"example-api-key"}]}]}\n'
  }
  signing=(
    II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64="$(base64 <"$keystore" | tr -d '\n')"
    II_OS_ANDROID_KEY_PROPERTIES="$(printf 'keyAlias=example-upload\nkeyPassword=%s\nstorePassword=%s\n' "$password" "$password")"
  )
  expect_refusal 'Android Firebase config belongs to the wrong project' \
    -i "${materialize_settings[@]}" "${signing[@]}" \
    II_OS_ANDROID_GOOGLE_SERVICES_JSON="$(google_services another-project)" \
    bash "$source_root/tool/materialize_android_release.sh"
  find "$fixture/runner" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  rm -f "$source_root/android/key.properties" \
    "$source_root/android/app/google-services.json"
  : >"$fixture/github.env"
  env -i "${materialize_settings[@]}" "${signing[@]}" \
    II_OS_ANDROID_GOOGLE_SERVICES_JSON="$(google_services example-project)" \
    bash "$source_root/tool/materialize_android_release.sh" >/dev/null
  grep -Fxq 'II_OS_FIREBASE_PROJECT_ID=example-project' "$fixture/github.env"
  grep -Fxq 'II_OS_FIREBASE_AUTH_DOMAIN=example-project.firebaseapp.com' \
    "$fixture/github.env"
  [[ -f "$source_root/android/key.properties" ]]

  # A changed run marker or replaced output preserves every file and the state.
  state_root="$fixture/runner/ii-os-android-release-7-1"
  cleanup_settings=(PATH="$PATH" RUNNER_TEMP="$fixture/runner" GITHUB_RUN_ID=7
    GITHUB_RUN_ATTEMPT=1 II_OS_ANDROID_RELEASE_STATE="$state_root")
  printf 'other run\n' > "$state_root/.ii-disposable-owner"
  expect_refusal 'Refusing to remove Android release state without matching ownership' \
    -i "${cleanup_settings[@]}" bash "$source_root/tool/cleanup_android_release.sh"
  [[ -f "$source_root/android/key.properties" ]]
  printf 'ii-os-android-release:7:1\n' > "$state_root/.ii-disposable-owner"
  rm "$source_root/android/app/google-services.json"
  printf 'replacement user config\n' > "$source_root/android/app/google-services.json"
  expect_refusal 'Refusing to remove Android configuration without matching ownership' \
    -i "${cleanup_settings[@]}" bash "$source_root/tool/cleanup_android_release.sh"
  [[ -f "$source_root/android/key.properties" && -d "$state_root" ]]
  grep -Fxq 'replacement user config' "$source_root/android/app/google-services.json"
  rm "$source_root/android/app/google-services.json"
  ln -s "$state_root/google-services.json" "$source_root/android/app/google-services.json"
  env -i "${cleanup_settings[@]}" bash "$source_root/tool/cleanup_android_release.sh"
  [[ ! -e "$source_root/android/key.properties" && ! -L "$source_root/android/key.properties" ]]
  [[ ! -e "$state_root" ]]

  # A validation build uses throwaway signing and a synthetic project for the
  # operator's own application id, and hands that project to the build step.
  cp "$repo_root/tool/materialize_disposable_android_validation.sh" \
    "$source_root/tool/"
  find "$fixture/runner" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  rm -f "$source_root/android/key.properties" \
    "$source_root/android/app/google-services.json"
  : >"$fixture/github.env"
  (
    cd "$source_root"
    env -i PATH="$PATH" RUNNER_TEMP="$fixture/runner" \
      GITHUB_ENV="$fixture/github.env" GITHUB_RUN_ID=8 GITHUB_RUN_ATTEMPT=1 \
      II_OS_ANDROID_APPLICATION_ID=org.example.app \
      bash tool/materialize_disposable_android_validation.sh >/dev/null
  )
  grep -Fxq 'II_OS_FIREBASE_PROJECT_ID=example-validation-project' \
    "$fixture/github.env"
  grep -Fxq 'II_OS_FIREBASE_EXPECTED_PROJECT_ID=example-validation-project' \
    "$fixture/github.env"
  grep -Fq 'org.example.app' "$source_root/android/app/google-services.json"
fi

# Toolchain bootstrap installs system packages, so a persistent self-hosted
# machine is refused. Inside a container this case cannot be exercised safely.
if [[ ! -f /.dockerenv ]]; then
  cp "$repo_root/tool/bootstrap_android_release_toolchain.sh" "$source_root/tool/"
  expect_refusal 'Android releases require a disposable Linux runner' \
    -i PATH="$PATH" RUNNER_ENVIRONMENT=self-hosted RUNNER_TEMP="$fixture/runner" \
    bash "$source_root/tool/bootstrap_android_release_toolchain.sh"
fi

# Store upload names the one workflow allowed to publish.
expect_refusal 'II_OS_ANDROID_UPLOAD_WORKFLOW is required' -i PATH="$PATH" \
  II_OS_WORKFLOW_REPOSITORY=acme-co/example-app II_OS_WORKFLOW_BRANCH=main \
  GITHUB_REPOSITORY=acme-co/example-app GITHUB_REF=refs/heads/main \
  bash "$source_root/tool/upload_android_internal.sh"

printf 'android release settings test: ok\n'
