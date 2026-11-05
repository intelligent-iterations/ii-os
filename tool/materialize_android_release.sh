#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "$name is required" >&2
    exit 1
  fi
}

# The application id and Firebase project are the operator's settings; the
# Firebase configuration must belong to exactly that project and package.
for name in \
  RUNNER_TEMP \
  GITHUB_ENV \
  GITHUB_RUN_ID \
  GITHUB_RUN_ATTEMPT \
  II_OS_ANDROID_APPLICATION_ID \
  II_OS_FIREBASE_EXPECTED_PROJECT_ID \
  II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64 \
  II_OS_ANDROID_KEY_PROPERTIES \
  II_OS_ANDROID_GOOGLE_SERVICES_JSON; do
  require_env "$name"
done
expected_package="$II_OS_ANDROID_APPLICATION_ID"
expected_project="$II_OS_FIREBASE_EXPECTED_PROJECT_ID"

key_properties="$repo_root/android/key.properties"
google_services="$repo_root/android/app/google-services.json"
if [[ -L "$repo_root/android" || -L "$repo_root/android/app" ||
      -e "$key_properties" || -L "$key_properties" ||
      -e "$google_services" || -L "$google_services" ]]; then
  echo 'Refusing to overwrite existing Android release configuration' >&2
  exit 1
fi
state_root="$RUNNER_TEMP/ii-os-android-release-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
if [[ -e "$state_root" || -L "$state_root" ]]; then
  echo "Refusing to reuse Android release state: $state_root" >&2
  exit 1
fi
install -d -m 0700 "$state_root"
printf '%s\n' "ii-os-android-release:$GITHUB_RUN_ID:$GITHUB_RUN_ATTEMPT" \
  > "$state_root/.ii-disposable-owner"
chmod 0600 "$state_root/.ii-disposable-owner"
# Expose the owned state even if input validation fails, so the workflow's
# always-cleanup step can remove only this run's partial materialization.
printf 'II_OS_ANDROID_RELEASE_STATE=%s\n' "$state_root" >> "$GITHUB_ENV"

keystore="$state_root/upload-keystore.jks"
printf '%s' "$II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64" | base64 --decode > "$keystore"
chmod 0600 "$keystore"

properties_json="$state_root/key-properties.json"
KEY_PROPERTIES_CONTENT="$II_OS_ANDROID_KEY_PROPERTIES" \
  python3 - "$properties_json" <<'PY'
import json
import os
import sys

values = {}
for raw_line in os.environ["KEY_PROPERTIES_CONTENT"].splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    key, separator, value = line.partition("=")
    if not separator or not key.strip() or not value.strip():
        raise SystemExit("II_OS_ANDROID_KEY_PROPERTIES contains an invalid line")
    values[key.strip()] = value.strip()

required = {"keyAlias", "keyPassword", "storePassword"}
missing = sorted(required - values.keys())
if missing:
    raise SystemExit(f"II_OS_ANDROID_KEY_PROPERTIES is missing: {', '.join(missing)}")
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({key: values[key] for key in sorted(required)}, handle)
PY
chmod 0600 "$properties_json"

key_alias="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["keyAlias"])' "$properties_json")"
key_password="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["keyPassword"])' "$properties_json")"
store_password="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["storePassword"])' "$properties_json")"

export II_OS_ANDROID_STORE_PASSWORD="$store_password"
keytool -list \
  -keystore "$keystore" \
  -storepass:env II_OS_ANDROID_STORE_PASSWORD \
  -alias "$key_alias" >/dev/null
unset II_OS_ANDROID_STORE_PASSWORD

install -m 0600 /dev/null "$state_root/key.properties"
{
  printf 'keyAlias=%s\n' "$key_alias"
  printf 'keyPassword=%s\n' "$key_password"
  printf 'storePassword=%s\n' "$store_password"
  printf 'storeFile=%s\n' "$keystore"
} > "$state_root/key.properties"

install -m 0600 /dev/null "$state_root/google-services.json"
printf '%s' "$II_OS_ANDROID_GOOGLE_SERVICES_JSON" > "$state_root/google-services.json"

firebase_env="$state_root/firebase.env"
python3 - "$state_root/google-services.json" "$firebase_env" "$expected_package" "$expected_project" <<'PY'
import json
import sys

source, destination, expected_package, expected_project = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    config = json.load(handle)

project = config.get("project_info") or {}
if project.get("project_id") != expected_project:
    raise SystemExit("Android Firebase config belongs to the wrong project")

matching = []
for client in config.get("client") or []:
    info = (client.get("client_info") or {}).get("android_client_info") or {}
    if info.get("package_name") == expected_package:
        matching.append(client)
if len(matching) != 1:
    raise SystemExit(
        "Android Firebase config must contain exactly one client for "
        "II_OS_ANDROID_APPLICATION_ID"
    )
client = matching[0]

api_keys = [item.get("current_key", "").strip() for item in client.get("api_key") or []]
api_keys = [value for value in api_keys if value]
oauth_clients = [
    item.get("client_id", "").strip()
    for item in client.get("oauth_client") or []
    if item.get("client_type") == 3
]
oauth_clients = [value for value in oauth_clients if value]
app_id = ((client.get("client_info") or {}).get("mobilesdk_app_id") or "").strip()
sender_id = str(project.get("project_number") or "").strip()
if len(api_keys) != 1 or len(oauth_clients) != 1 or not app_id or not sender_id:
    raise SystemExit("Android Firebase config is missing required app or OAuth values")

values = {
    "II_OS_FIREBASE_API_KEY": api_keys[0],
    "II_OS_FIREBASE_APP_ID": app_id,
    "II_OS_FIREBASE_MESSAGING_SENDER_ID": sender_id,
    "II_OS_FIREBASE_PROJECT_ID": expected_project,
    "II_OS_FIREBASE_AUTH_DOMAIN": f"{expected_project}.firebaseapp.com",
    "II_OS_GOOGLE_ANDROID_SERVER_CLIENT_ID": oauth_clients[0],
}
with open(destination, "w", encoding="utf-8") as handle:
    for key, value in values.items():
        if "\n" in value or "\r" in value:
            raise SystemExit(f"Firebase value for {key} contains a newline")
        handle.write(f"{key}={value}\n")
PY
chmod 0600 "$firebase_env"
# Atomic creation without replacement; cleanup recognizes only these exact
# links to this run's owner-marked private state.
python3 - "$state_root" "$key_properties" "$google_services" <<'PY'
import os
import sys

state, *destinations = sys.argv[1:]
for destination in destinations:
    os.symlink(os.path.join(state, os.path.basename(destination)), destination)
PY
cat "$firebase_env" >> "$GITHUB_ENV"
{
  printf 'II_OS_ANDROID_KEYSTORE_PATH=%s\n' "$keystore"
} >> "$GITHUB_ENV"

unset \
  II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64 \
  II_OS_ANDROID_KEY_PROPERTIES \
  II_OS_ANDROID_GOOGLE_SERVICES_JSON \
  key_alias key_password store_password

echo "Android signing and Firebase files validated and materialized."
