import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/generation_history.dart';

void main() {
  test('reads explicit immutable generation metadata', () {
    final entry = HistoryEntryModel.fromJobArtifact(
      job: {
        'jobId': 'job-1',
        'repository': 'acme/media',
        'status': 'completed',
        'submittedAt': '2026-07-15T12:00:00Z',
        'inputs': {'prompt': 'An older prompt value'},
        'generationMetadata': {
          'prompt': 'Change her haircut to a bob',
          'model': 'Acme Edit v2',
          'workflowKey': 'acme/media#image-edit',
        },
      },
      artifact: {
        'path': 'workspaces/test/runs/job-1/output.png',
        'content_type': 'image/png',
      },
    );

    expect(entry.generation.prompt, 'Change her haircut to a bob');
    expect(entry.generation.model, 'Acme Edit v2');
    expect(entry.generation.workflowKey, 'acme/media#image-edit');
    expect(entry.filename, 'output.png');
    expect(entry.isGeneratedMedia, isTrue);
  });

  test('keeps legacy history readable from existing job fields', () {
    final metadata = GenerationMetadataModel.fromJob({
      'kind': 'image-edit',
      'workflowName': 'Legacy Image Edit',
      'inputs': {'prompt': 'Make the hair shorter'},
    });

    expect(metadata.prompt, 'Make the hair shorter');
    expect(metadata.model, 'Legacy Image Edit');
    expect(metadata.workflowKey, 'image-edit');
  });

  test('includes generated audio in media history', () {
    final entry = HistoryEntryModel.fromJobArtifact(
      job: const {'jobId': 'song-1'},
      artifact: const {
        'path': 'workspaces/test/runs/song-1/audio/song.mp3',
        'content_type': 'audio/mpeg',
      },
    );

    expect(entry.isAudio, isTrue);
    expect(entry.isGeneratedMedia, isTrue);
  });

  test('normalizes media type casing before picker classification', () {
    final image = HistoryEntryModel.fromJobArtifact(
      job: const {'jobId': 'image-1'},
      artifact: const {
        'path': 'workspaces/test/runs/image-1/image.png',
        'content_type': ' Image/PNG ',
      },
    );
    final video = HistoryEntryModel.fromJobArtifact(
      job: const {'jobId': 'video-1'},
      artifact: const {
        'path': 'workspaces/test/runs/video-1/video.mp4',
        'content_type': 'Video/MP4',
      },
    );

    expect(image.contentType, 'image/png');
    expect(image.isImage, isTrue);
    expect(video.contentType, 'video/mp4');
    expect(video.isVideo, isTrue);
  });

  group('video posters', () {
    Map<String, Object?> videoArtifact() => {
      'path': 'workspaces/test/runs/job-1/clip.mp4',
      'content_type': 'video/mp4',
    };
    Map<String, Object?> posterArtifact() => {
      'path': 'workspaces/test/runs/job-1/clip-poster.png',
      'content_type': 'image/png',
      'role': 'poster',
      'poster_for': 'workspaces/test/runs/job-1/clip.mp4',
    };

    test('a video draws its poster and nothing else does', () {
      final withPoster = HistoryEntryModel.fromJobArtifact(
        job: const {'jobId': 'job-1'},
        artifact: videoArtifact(),
        poster: posterArtifact(),
      );
      final withoutPoster = HistoryEntryModel.fromJobArtifact(
        job: const {'jobId': 'job-1'},
        artifact: videoArtifact(),
      );

      expect(withPoster.isVideo, isTrue);
      expect(withPoster.previewArtifact, posterArtifact());
      // Absent a poster the card has to keep its placeholder rather than
      // reaching for the video and decoding it to draw a grid cell.
      expect(withoutPoster.previewArtifact, isNull);
    });

    test('an image still depicts itself', () {
      final entry = HistoryEntryModel.fromJobArtifact(
        job: const {'jobId': 'job-1'},
        artifact: const {
          'path': 'workspaces/test/runs/job-1/image.png',
          'content_type': 'image/png',
        },
      );

      expect(entry.previewArtifact, entry.artifact);
    });

    test('audio has no frame to show', () {
      final entry = HistoryEntryModel.fromJobArtifact(
        job: const {'jobId': 'job-1'},
        artifact: const {
          'path': 'workspaces/test/runs/job-1/voice.mp3',
          'content_type': 'audio/mpeg',
        },
      );

      expect(entry.previewArtifact, isNull);
      expect(entry.isAudio, isTrue);
    });

    test('a poster identifies itself and what it depicts', () {
      final entry = HistoryEntryModel.fromJobArtifact(
        job: const {'jobId': 'job-1'},
        artifact: posterArtifact(),
      );

      expect(entry.isPoster, isTrue);
      expect(entry.posterFor, 'workspaces/test/runs/job-1/clip.mp4');
    });
  });
}
