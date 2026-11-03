import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/repositories/video_project_repository.dart';

void main() {
  test('project listing preserves the server render capability state', () {
    final listing = parseVideoProjectListing({
      'projects': const [],
      'renderCapability': {
        'status': 'available',
        'requiredCapabilities': ['ffmpeg-client-validation', 'runtime-docker'],
        'minimumCpu': 4,
        'minimumRamMiB': 8192,
      },
    });

    expect(listing.projects, isEmpty);
    expect(listing.renderCapability.isAvailable, isTrue);
  });

  test('missing capability remains unknown', () {
    final listing = parseVideoProjectListing({'projects': const []});

    expect(listing.renderCapability.isAvailable, isFalse);
    expect(listing.renderCapability.status.name, 'unknown');
  });
}
