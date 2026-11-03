import 'package:ii_ffmpeg_universal/src/backends/web_asset_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package assets resolve from the document base on a deep app route', () {
    final resolved = resolveWebAssetLocation(
      value:
          'assets/packages/ii_ffmpeg_universal/assets/web/'
          'ii_ffmpeg_universal_bridge.js',
      pageLocation: Uri.parse(
        'https://app.example/workspaces/workspace-1/playground',
      ),
      documentBaseLocation: 'https://app.example/',
    );

    expect(
      resolved,
      Uri.parse(
        'https://app.example/assets/packages/ii_ffmpeg_universal/'
        'assets/web/ii_ffmpeg_universal_bridge.js',
      ),
    );
  });
}
