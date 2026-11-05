#!/usr/bin/env bash
# Materializes throwaway signing and a synthetic Firebase configuration for the
# operator's own application id, so a validation build needs no store or
# Firebase credential. Its upload key is generated for this run only, so the
# resulting bundle can never be published.
set -euo pipefail

package="${II_OS_ANDROID_APPLICATION_ID:-}"
[[ -n "$package" ]] || {
  echo 'II_OS_ANDROID_APPLICATION_ID is required' >&2
  exit 1
}
validation_project=example-validation-project

input_root="$(mktemp -d "$RUNNER_TEMP/ii-os-android-validation.XXXXXX")"
owner="$input_root/.ii-disposable-owner"
expected="ii-os-android-validation:${GITHUB_RUN_ID:?}:${GITHUB_RUN_ATTEMPT:?}"
printf '%s\n' "$expected" > "$owner"
chmod 0600 "$owner"

cleanup() {
  if [[ ! -f "$owner" || "$(cat "$owner")" != "$expected" ]]; then
    echo "Refusing to remove validation input without matching ownership" >&2
    return 1
  fi
  rm -rf -- "$input_root"
}
trap cleanup EXIT

password="$(openssl rand -hex 24)"
export II_OS_VALIDATION_KEY_PASSWORD="$password"
keystore="$input_root/disposable-upload.jks"
keytool -genkeypair \
  -keystore "$keystore" \
  -storepass:env II_OS_VALIDATION_KEY_PASSWORD \
  -keypass:env II_OS_VALIDATION_KEY_PASSWORD \
  -alias disposable-validation \
  -keyalg RSA \
  -keysize 3072 \
  -validity 1 \
  -dname 'CN=Disposable ii-os CI validation,OU=CI,O=Example,C=US' \
  -noprompt >/dev/null 2>&1

keystore_base64="$(base64 <"$keystore" | tr -d '\n')"
key_properties_content="$(printf '%s\n' \
  'keyAlias=disposable-validation' \
  "keyPassword=$password" \
  "storePassword=$password")"
export II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64="$keystore_base64"
export II_OS_ANDROID_KEY_PROPERTIES="$key_properties_content"
google_services_json="$(
  VALIDATION_PACKAGE="$package" VALIDATION_PROJECT="$validation_project" \
    python3 -c '
import json
import os

project = os.environ["VALIDATION_PROJECT"]
print(json.dumps({
    "project_info": {
        "project_number": "000000000000",
        "project_id": project,
        "storage_bucket": f"{project}.firebasestorage.app",
    },
    "client": [{
        "client_info": {
            "mobilesdk_app_id": "1:000000000000:android:0000000000000000",
            "android_client_info": {"package_name": os.environ["VALIDATION_PACKAGE"]},
        },
        "oauth_client": [{
            "client_id": "000000000000-validation.apps.googleusercontent.com",
            "client_type": 3,
        }],
        "api_key": [{"current_key": "validation-only-not-a-real-api-key"}],
    }],
    "configuration_version": "1",
}))
'
)"
export II_OS_ANDROID_GOOGLE_SERVICES_JSON="$google_services_json"

II_OS_FIREBASE_EXPECTED_PROJECT_ID="$validation_project" \
  tool/materialize_android_release.sh
printf 'II_OS_FIREBASE_EXPECTED_PROJECT_ID=%s\n' "$validation_project" \
  >>"${GITHUB_ENV:?}"
unset \
  II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64 \
  II_OS_ANDROID_KEY_PROPERTIES \
  II_OS_ANDROID_GOOGLE_SERVICES_JSON \
  II_OS_VALIDATION_KEY_PASSWORD \
  password
