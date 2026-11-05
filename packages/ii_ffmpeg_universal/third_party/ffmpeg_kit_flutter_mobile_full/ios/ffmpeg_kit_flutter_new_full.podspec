Pod::Spec.new do |s|
  s.name             = 'ffmpeg_kit_flutter_new_full'
  s.version          = '8.1.2'
  s.summary          = 'FFmpeg Kit for Flutter'
  s.description      = 'A Flutter plugin for running FFmpeg and FFprobe commands.'
  s.homepage         = 'https://github.com/sk3llo/ffmpeg_kit_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Anton Karpenko' => 'kapraton@gmail.com' }

  s.platform            = :ios
  s.requires_arc        = true
  s.static_framework    = true

  s.source              = { :path => '.' }
  s.source_files        = 'ffmpeg_kit_flutter_new_full/Sources/ffmpeg_kit_flutter_new_full/**/*.{h,m}'
  s.public_header_files = 'ffmpeg_kit_flutter_new_full/Sources/ffmpeg_kit_flutter_new_full/include/**/*.h'

  s.default_subspec = 'full'

  s.dependency          'Flutter'
  # The vendored xcframeworks ship a native arm64 iOS-simulator slice, so arm64
  # must NOT be excluded for the simulator (required by Apple Silicon / Xcode 26+).
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.script_phase = {
    :name => 'Require source-attested FFmpeg for release',
    :execution_position => :before_compile,
    :script => <<-SCRIPT
      set -euo pipefail
      case "${CONFIGURATION:-}" in
        *Release*)
          test -n "${II_FFMPEG_IOS_ARCHIVE_DIR:-}"
          test -n "${II_FFMPEG_IOS_ATTESTATION:-}"
          test "${II_FFMPEG_ALLOW_DEBUG_FALLBACK:-false}" != true
          cd "${PODS_TARGET_SRCROOT}"
          II_FFMPEG_REQUIRE_RELEASE_ENGINE=true \
            bash "${PODS_TARGET_SRCROOT}/../scripts/setup_ios.sh" --verify-only
          ;;
      esac
    SCRIPT
  }

  s.subspec 'full' do |ss|
    # Always run the verifier. It compares cached frameworks with freshly
    # downloaded, archive-checksummed trees and fails closed when offline.
    s.prepare_command = <<-CMD
      chmod +x ../scripts/setup_ios.sh
      ../scripts/setup_ios.sh
    CMD
    ss.source_files         = 'ffmpeg_kit_flutter_new_full/Sources/ffmpeg_kit_flutter_new_full/**/*.{h,m}'
    ss.public_header_files  = 'ffmpeg_kit_flutter_new_full/Sources/ffmpeg_kit_flutter_new_full/include/**/*.h'
    ss.ios.vendored_frameworks = 'Frameworks/ffmpegkit.xcframework',
                                 'Frameworks/libavcodec.xcframework',
                                 'Frameworks/libavdevice.xcframework',
                                 'Frameworks/libavfilter.xcframework',
                                 'Frameworks/libavformat.xcframework',
                                 'Frameworks/libavutil.xcframework',
                                 'Frameworks/libswresample.xcframework',
                                 'Frameworks/libswscale.xcframework'
    ss.ios.deployment_target = '14.0'
  end
end
