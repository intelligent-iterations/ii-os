#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
command_name="${1:-}"
owner="ii-os-app-store:${GITHUB_RUN_ID:?}:${GITHUB_RUN_ATTEMPT:?}"

fail() {
  printf 'iOS App Store release failed: %s\n' "$1" >&2
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "$name is required"
}

decode_base64() {
  if printf dGVzdA== | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

validate_runner_temp() {
  [[ "${RUNNER_TEMP:?}" == /* && -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] ||
    fail 'RUNNER_TEMP must be a real absolute directory'
}

validate_owned_state() {
  local state="${II_OS_IOS_RELEASE_DIR:?}"
  [[ "$state" == "$RUNNER_TEMP"/* && -d "$state" && ! -L "$state" ]] ||
    fail 'release state is outside RUNNER_TEMP or unsafe'
  [[ -f "$state/.ii-disposable-owner" && ! -L "$state/.ii-disposable-owner" ]] ||
    fail 'release ownership marker is missing or unsafe'
  [[ "$(<"$state/.ii-disposable-owner")" == "$owner" ]] ||
    fail 'release ownership marker belongs to another run'
}

prepare() {
  validate_runner_temp
  require_value GITHUB_ENV
  for name in \
    APPLE_TEAM_ID \
    IOS_BUNDLE_ID \
    APPLE_API_KEY \
    APPLE_API_KEY_ID \
    APPLE_ISSUER_ID \
    IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64 \
    IOS_DISTRIBUTION_CERTIFICATE_PASSWORD \
    II_OS_DEV_IOS_PROVISIONING_PROFILE_BASE64 \
    II_OS_IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64; do
    require_value "$name"
  done

  local state="$RUNNER_TEMP/ii-os-app-store-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
  [[ ! -e "$state" && ! -L "$state" ]] ||
    fail 'release state path is already occupied'
  mkdir -m 0700 "$state"
  printf '%s\n' "$owner" >"$state/.ii-disposable-owner"
  printf 'II_OS_IOS_RELEASE_DIR=%s\n' "$state" >>"$GITHUB_ENV"

  local keychain_password keychain cert profile profile_plist
  local api_key api_key_json firebase_plist project_backup
  keychain_password="$(uuidgen)"
  keychain="$state/signing.keychain-db"
  cert="$state/distribution.p12"
  profile="$state/distribution.mobileprovision"
  profile_plist="$state/profile.plist"
  api_key="$state/AuthKey.p8"
  api_key_json="$state/app-store-connect-api-key.json"
  firebase_plist="$state/GoogleService-Info.plist"
  project_backup="$state/project.pbxproj.original"
  {
    printf 'II_OS_IOS_KEYCHAIN_PATH=%s\n' "$keychain"
    printf 'II_OS_IOS_ASC_API_KEY_JSON=%s\n' "$api_key_json"
    printf 'II_OS_IOS_PROJECT_BACKUP=%s\n' "$project_backup"
  } >>"$GITHUB_ENV"

  printf '%s' "$IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64" |
    tr -d '\n' | decode_base64 >"$cert"
  printf '%s' "$II_OS_DEV_IOS_PROVISIONING_PROFILE_BASE64" |
    tr -d '\n' | decode_base64 >"$profile"
  printf '%s' "$II_OS_IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64" |
    tr -d '\n' | decode_base64 >"$firebase_plist"
  if printf '%s' "$APPLE_API_KEY" | grep -q 'BEGIN PRIVATE KEY'; then
    printf '%s' "$APPLE_API_KEY" >"$api_key"
  else
    printf '%s' "$APPLE_API_KEY" | tr -d '\n' | decode_base64 >"$api_key"
  fi
  for path in "$cert" "$profile" "$firebase_plist" "$api_key"; do
    [[ -s "$path" && ! -L "$path" ]] || fail "materialized file is empty: $path"
  done

  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  security import "$cert" -k "$keychain" \
    -P "$IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain"
  local current_keychains=()
  while IFS= read -r current; do
    current_keychains+=("${current//\"/}")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "$keychain" "${current_keychains[@]}"
  security find-identity -v -p codesigning "$keychain" |
    grep -F 'Apple Distribution'

  security cms -D -i "$profile" >"$profile_plist"
  local profile_uuid profile_name app_identifier installed_profile
  profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$profile_plist")"
  profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$profile_plist")"
  app_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_plist")"
  [[ "$app_identifier" == "$APPLE_TEAM_ID.$IOS_BUNDLE_ID" ]] ||
    fail 'provisioning profile belongs to another application'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:aps-environment' "$profile_plist")" == production ]] ||
    fail 'provisioning profile does not enable production notifications'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$profile_plist")" == false ]] ||
    fail 'provisioning profile is not a distribution profile'
  mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
  installed_profile="$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
  [[ ! -e "$installed_profile" && ! -L "$installed_profile" ]] ||
    fail 'provisioning profile destination is already occupied'
  cp "$profile" "$installed_profile"
  printf 'II_OS_IOS_INSTALLED_PROFILE=%s\n' "$installed_profile" >>"$GITHUB_ENV"

  [[ "$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$firebase_plist")" == "$IOS_BUNDLE_ID" ]] ||
    fail 'Firebase configuration belongs to another application'
  local runner_plist="$repo_root/ios/Runner/GoogleService-Info.plist"
  [[ ! -e "$runner_plist" && ! -L "$runner_plist" ]] ||
    fail 'Runner Firebase configuration path is already occupied'
  cp "$firebase_plist" "$runner_plist"

  local project="$repo_root/ios/Runner.xcodeproj/project.pbxproj"
  cp "$project" "$project_backup"
  PROFILE_NAME="$profile_name" ruby <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |candidate| candidate.name == 'Runner' }
runner = project.main_group.groups.find { |group| group.display_name == 'Runner' }
raise 'Runner target or group not found' unless target && runner
firebase = runner.files.find { |file| file.path == 'GoogleService-Info.plist' } || runner.new_file('GoogleService-Info.plist')
unless target.resources_build_phase.files_references.include?(firebase)
  target.resources_build_phase.add_file_reference(firebase, true)
end
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = ENV.fetch('IOS_BUNDLE_ID')
  config.build_settings['DEVELOPMENT_TEAM'] = ENV.fetch('APPLE_TEAM_ID')
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  config.build_settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Distribution'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = ENV.fetch('PROFILE_NAME')
end
project.save
RUBY

  ASC_JSON_PATH="$api_key_json" ASC_KEY_PATH="$api_key" ruby -rjson -e \
    'File.write(ENV.fetch("ASC_JSON_PATH"), JSON.pretty_generate({key_id: ENV.fetch("APPLE_API_KEY_ID"), issuer_id: ENV.fetch("APPLE_ISSUER_ID"), key: File.read(ENV.fetch("ASC_KEY_PATH")), duration: 1200, in_house: false}))'

  {
    printf 'II_OS_IOS_PROFILE_NAME=%s\n' "$profile_name"
  } >>"$GITHUB_ENV"
}

build() {
  validate_runner_temp
  validate_owned_state
  for name in \
    APPLE_TEAM_ID IOS_BUNDLE_ID BUILD_NAME BUILD_NUMBER \
    II_OS_FIREBASE_AUTH_DOMAIN II_OS_CONTROL_API_BASE_URL \
    II_OS_IOS_PROFILE_NAME II_OS_IOS_RELEASE_DIR; do
    require_value "$name"
  done
  local state="$II_OS_IOS_RELEASE_DIR"
  local export_options="$state/ExportOptions.plist"
  EXPORT_OPTIONS="$export_options" ruby -e '
    require "xcodeproj"
    data = {
      "method" => "app-store-connect",
      "signingStyle" => "manual",
      "teamID" => ENV.fetch("APPLE_TEAM_ID"),
      "provisioningProfiles" => {
        ENV.fetch("IOS_BUNDLE_ID") => ENV.fetch("II_OS_IOS_PROFILE_NAME")
      },
      "stripSwiftSymbols" => true,
      "compileBitcode" => false,
      "manageAppVersionAndBuildNumber" => false
    }
    Xcodeproj::Plist.write_to_path(data, ENV.fetch("EXPORT_OPTIONS"))
  '

  local firebase_plist="$repo_root/ios/Runner/GoogleService-Info.plist"
  local api_key app_id sender_id project_id client_id
  api_key="$(/usr/libexec/PlistBuddy -c 'Print :API_KEY' "$firebase_plist")"
  app_id="$(/usr/libexec/PlistBuddy -c 'Print :GOOGLE_APP_ID' "$firebase_plist")"
  sender_id="$(/usr/libexec/PlistBuddy -c 'Print :GCM_SENDER_ID' "$firebase_plist")"
  project_id="$(/usr/libexec/PlistBuddy -c 'Print :PROJECT_ID' "$firebase_plist")"
  client_id="$(/usr/libexec/PlistBuddy -c 'Print :CLIENT_ID' "$firebase_plist")"

  cd "$repo_root"
  flutter pub get --enforce-lockfile
  flutter build ipa \
    --release \
    --build-name "$BUILD_NAME" \
    --build-number "$BUILD_NUMBER" \
    --export-options-plist "$export_options" \
    --dart-define="II_OS_FIREBASE_API_KEY=$api_key" \
    --dart-define="II_OS_FIREBASE_APP_ID=$app_id" \
    --dart-define="II_OS_FIREBASE_MESSAGING_SENDER_ID=$sender_id" \
    --dart-define="II_OS_FIREBASE_PROJECT_ID=$project_id" \
    --dart-define="II_OS_FIREBASE_AUTH_DOMAIN=$II_OS_FIREBASE_AUTH_DOMAIN" \
    --dart-define="II_OS_GOOGLE_IOS_CLIENT_ID=$client_id" \
    --dart-define="II_OS_CONTROL_API_BASE_URL=$II_OS_CONTROL_API_BASE_URL" \
    --dart-define="II_OS_SONG_RENDER_PROFILES_JSON=${II_OS_SONG_RENDER_PROFILES_JSON:-}"

  local ipa_path verification_dir built_app
  ipa_path="$(find "$repo_root/build/ios/ipa" -name '*.ipa' -type f | head -n 1)"
  [[ -n "$ipa_path" && -f "$ipa_path" && ! -L "$ipa_path" ]] ||
    fail 'signed IPA was not produced'
  verification_dir="$state/ipa-verification"
  mkdir -m 0700 "$verification_dir"
  unzip -q "$ipa_path" -d "$verification_dir"
  built_app="$(find "$verification_dir/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)"
  [[ -n "$built_app" ]] || fail 'IPA does not contain an application bundle'
  codesign --verify --deep --strict "$built_app"
  codesign -d --entitlements :- "$built_app" >"$state/signed-entitlements.plist" 2>/dev/null
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$state/signed-entitlements.plist")" == production ]] ||
    fail 'signed IPA does not carry production notification entitlement'
  security cms -D -i "$built_app/embedded.mobileprovision" >"$state/embedded-profile.plist"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$state/embedded-profile.plist")" == "$APPLE_TEAM_ID.$IOS_BUNDLE_ID" ]] ||
    fail 'signed IPA belongs to another application'
  printf 'II_OS_IOS_IPA_PATH=%s\n' "$ipa_path" >>"${GITHUB_ENV:?}"
}

upload() {
  validate_runner_temp
  validate_owned_state
  for name in IOS_BUNDLE_ID II_OS_IOS_ASC_API_KEY_JSON II_OS_IOS_IPA_PATH; do
    require_value "$name"
  done
  [[ -f "$II_OS_IOS_ASC_API_KEY_JSON" && ! -L "$II_OS_IOS_ASC_API_KEY_JSON" ]] ||
    fail 'App Store Connect API key file is unsafe'
  [[ -f "$II_OS_IOS_IPA_PATH" && ! -L "$II_OS_IOS_IPA_PATH" ]] ||
    fail 'signed IPA path is unsafe'
  fastlane pilot upload \
    --api_key_path "$II_OS_IOS_ASC_API_KEY_JSON" \
    --app_identifier "$IOS_BUNDLE_ID" \
    --ipa "$II_OS_IOS_IPA_PATH" \
    --skip_waiting_for_build_processing false
}

cleanup() {
  validate_runner_temp
  local state="${II_OS_IOS_RELEASE_DIR:-}"
  [[ -n "$state" ]] || return 0
  validate_owned_state

  local installed_profile="${II_OS_IOS_INSTALLED_PROFILE:-}"
  if [[ -n "$installed_profile" && -f "$installed_profile" && ! -L "$installed_profile" ]]; then
    cmp -s "$installed_profile" "$state/distribution.mobileprovision" ||
      fail 'installed provisioning profile changed during the run'
    rm -- "$installed_profile"
  fi

  local runner_plist="$repo_root/ios/Runner/GoogleService-Info.plist"
  if [[ -f "$runner_plist" && ! -L "$runner_plist" ]]; then
    cmp -s "$runner_plist" "$state/GoogleService-Info.plist" ||
      fail 'Runner Firebase configuration changed during the run'
    rm -- "$runner_plist"
  fi

  local project="$repo_root/ios/Runner.xcodeproj/project.pbxproj"
  if [[ -e "$state/project.pbxproj.original" ]]; then
    [[ "${II_OS_IOS_PROJECT_BACKUP:-}" == "$state/project.pbxproj.original" ]] ||
      fail 'Xcode project backup identity is invalid'
    [[ -f "$II_OS_IOS_PROJECT_BACKUP" && ! -L "$II_OS_IOS_PROJECT_BACKUP" ]] ||
      fail 'Xcode project backup is unsafe'
    cp "$II_OS_IOS_PROJECT_BACKUP" "$project"
  fi

  if [[ -n "${II_OS_IOS_KEYCHAIN_PATH:-}" && -f "$II_OS_IOS_KEYCHAIN_PATH" ]]; then
    [[ "$II_OS_IOS_KEYCHAIN_PATH" == "$state/signing.keychain-db" ]] ||
      fail 'signing keychain identity is invalid'
    security delete-keychain "$II_OS_IOS_KEYCHAIN_PATH"
  fi
  rm -rf -- "$state"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf 'II_OS_IOS_RELEASE_DIR=\n' >>"$GITHUB_ENV"
  fi
}

case "$command_name" in
prepare) prepare ;;
build) build ;;
upload) upload ;;
cleanup) cleanup ;;
*) fail 'expected prepare, build, upload, or cleanup' ;;
esac
