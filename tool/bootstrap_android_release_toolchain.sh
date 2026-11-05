#!/usr/bin/env bash
set -euo pipefail

# This script installs system packages, which is safe only on a runner that is
# discarded after the job: a container, or a GitHub-hosted runner.
if [[ "$(uname -s)" != Linux ]] ||
  { [[ ! -f /.dockerenv ]] && [[ "${RUNNER_ENVIRONMENT:-}" != github-hosted ]]; }; then
  echo "Android releases require a disposable Linux runner: a container or a GitHub-hosted runner" >&2
  exit 1
fi

as_root() {
  if [[ "$(id -u)" == 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [[ "$(dpkg --print-architecture)" == arm64 ]]; then
  as_root dpkg --add-architecture amd64
fi
as_root env DEBIAN_FRONTEND=noninteractive apt-get update
packages=(
  ca-certificates
  curl
  jq
  openjdk-17-jdk-headless
  ruby-full
  unzip
)
as_root env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends "${packages[@]}"
as_root rm -rf /var/lib/apt/lists/*

java_home="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
android_home="$RUNNER_TEMP/android-sdk"
archive="$RUNNER_TEMP/commandlinetools-linux-15859902_latest.zip"
archive_sha='4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583'

curl -fsSL --retry 3 \
  'https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip' \
  -o "$archive"
printf '%s  %s\n' "$archive_sha" "$archive" | sha256sum -c -
install -d "$android_home/cmdline-tools"
unzip -q "$archive" -d "$android_home/cmdline-tools"
mv "$android_home/cmdline-tools/cmdline-tools" \
  "$android_home/cmdline-tools/latest"
rm -f "$archive"

export ANDROID_HOME="$android_home"
export ANDROID_SDK_ROOT="$android_home"
export JAVA_HOME="$java_home"
export PATH="$android_home/cmdline-tools/latest/bin:$android_home/platform-tools:$java_home/bin:$PATH"

yes | sdkmanager --licenses >/dev/null || true
sdk_packages=(
  'platform-tools'
  'platforms;android-36'
  'build-tools;36.0.0'
)
sdkmanager --install "${sdk_packages[@]}"

as_root gem install bundler --no-document
(
  cd android
  bundle config set --local path "$RUNNER_TEMP/bundle"
  bundle install --jobs 4 --retry 3
)
flutter config --android-sdk "$android_home"
flutter precache --android
for engine_dir in \
  "$FLUTTER_HOME"/bin/cache/artifacts/engine/android-*-profile \
  "$FLUTTER_HOME"/bin/cache/artifacts/engine/android-*-release; do
  if [[ -d "$engine_dir/linux-x64" && ! -e "$engine_dir/linux-arm64" ]]; then
    ln -s linux-x64 "$engine_dir/linux-arm64"
  fi
done

{
  printf 'ANDROID_HOME=%s\n' "$android_home"
  printf 'ANDROID_SDK_ROOT=%s\n' "$android_home"
  printf 'JAVA_HOME=%s\n' "$java_home"
  printf '%s\n' "$android_home/cmdline-tools/latest/bin" "$android_home/platform-tools" "$java_home/bin" \
    >> "$GITHUB_PATH"
} >> "$GITHUB_ENV"

flutter --version
java -version
sdkmanager --list_installed | grep -F 'platforms;android-36'
sdkmanager --list_installed | grep -F 'build-tools;36.0.0'
bundle --version
