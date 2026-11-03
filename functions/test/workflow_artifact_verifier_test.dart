import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/provider_contracts/artifact_storage_gateway.dart';
import 'package:ii_os_functions/src/workflow_artifact_verifier.dart';
import 'package:test/test.dart';

void main() {
  group('provider-neutral artifact verification', () {
    test('returns the configured provider upload contract', () async {
      final gateway = _FakeArtifactStorageGateway();
      final resolver = _FakeArtifactStorageResolver(gateway);
      final verifier = WorkflowArtifactVerifier(resolver);

      expect(await verifier.uploadContract('workspace-1'), {
        'provider': 'test_provider',
        'container': 'media',
      });
      expect(resolver.requests, [
        (workspaceId: 'workspace-1', permission: 'workflows.upload'),
      ]);
    });

    test('compares reports with provider-neutral object metadata', () async {
      final gateway = _FakeArtifactStorageGateway();
      final verifier = WorkflowArtifactVerifier(
        _FakeArtifactStorageResolver(gateway),
      );

      final artifacts = await verifier.verify(
        workspaceId: 'workspace-1',
        requestId: 'request-123',
        value: [_reportedArtifact],
      );

      expect(gateway.lookups.single.path, _reportedArtifact['path']);
      expect(gateway.lookups.single.version, _reportedArtifact['generation']);
      expect(artifacts.single['crc32c'], 'crc32c-value');
      expect(artifacts.single['verifiedAt'], isA<String>());
    });

    test('preserves the common failure code across providers', () async {
      final verifier = WorkflowArtifactVerifier(
        _FakeArtifactStorageResolver(
          _FakeArtifactStorageGateway(sizeBytes: 999),
        ),
      );

      expect(
        () => verifier.verify(
          workspaceId: 'workspace-1',
          requestId: 'request-123',
          value: [_reportedArtifact],
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'artifact_verification_failed',
          ),
        ),
      );
    });
  });

  test('normalizes media metadata inside the claimed request prefix', () {
    final artifacts = normalizeWorkflowArtifacts(
      [
        {
          'path': 'workspaces/workspace-1/runs/request-123/output/image.png',
          'contentType': 'image/png',
          'sizeBytes': 2048,
          'sha256': List.filled(64, 'a').join(),
          'generation': '1730000000000000',
        },
      ],
      workspaceId: 'workspace-1',
      requestId: 'request-123',
    );

    expect(artifacts.single['content_type'], 'image/png');
    expect(artifacts.single['size_bytes'], 2048);
  });

  test('rejects cross-workspace paths and unsupported content', () {
    for (final artifact in [
      {
        'path': 'workspaces/other/runs/request-123/output/image.png',
        'contentType': 'image/png',
      },
      {
        'path': 'workspaces/workspace-1/runs/request-123/output/file.zip',
        'contentType': 'application/zip',
      },
    ]) {
      expect(
        () => normalizeWorkflowArtifacts(
          [
            {
              ...artifact,
              'sizeBytes': 100,
              'sha256': List.filled(64, 'b').join(),
              'generation': '1',
            },
          ],
          workspaceId: 'workspace-1',
          requestId: 'request-123',
        ),
        throwsA(isA<ApiError>()),
      );
    }
  });

  test('accepts bounded generated song artifacts', () {
    final artifacts = normalizeWorkflowArtifacts(
      [
        {
          'path': 'workspaces/workspace-1/runs/request-123/audio/song.mp3',
          'contentType': 'audio/mpeg',
          'sizeBytes': 4096,
          'sha256': List.filled(64, 'c').join(),
          'generation': '1730000000000001',
        },
      ],
      workspaceId: 'workspace-1',
      requestId: 'request-123',
    );

    expect(artifacts.single['content_type'], 'audio/mpeg');
    expect(artifacts.single['path'], endsWith('/audio/song.mp3'));
  });

  test('accepts a bounded JSON decisions document', () {
    final artifacts = normalizeWorkflowArtifacts(
      [
        {
          'path':
              'workspaces/workspace-1/runs/request-123/open-jev/decisions.json',
          'contentType': 'application/json',
          'sizeBytes': 1024 * 1024,
          'sha256': List.filled(64, 'e').join(),
          'generation': '1730000000000003',
        },
      ],
      workspaceId: 'workspace-1',
      requestId: 'request-123',
    );

    expect(artifacts.single['content_type'], 'application/json');
    expect(artifacts.single['size_bytes'], 1024 * 1024);
  });

  test('a JSON document over 1 MiB is refused while media keeps its limit', () {
    Map<String, Object?> artifact(String contentType, int size) => {
      'path': 'workspaces/workspace-1/runs/request-123/output/result',
      'contentType': contentType,
      'sizeBytes': size,
      'sha256': List.filled(64, 'f').join(),
      'generation': '1730000000000004',
    };

    expect(
      () => normalizeWorkflowArtifacts(
        [artifact('application/json', 1024 * 1024 + 1)],
        workspaceId: 'workspace-1',
        requestId: 'request-123',
      ),
      throwsA(
        isA<ApiError>().having((e) => e.code, 'code', 'invalid_artifact'),
      ),
    );
    expect(
      normalizeWorkflowArtifacts(
        [artifact('video/mp4', 1024 * 1024 * 1024)],
        workspaceId: 'workspace-1',
        requestId: 'request-123',
      ).single['size_bytes'],
      1024 * 1024 * 1024,
    );
  });

  test('Ghost artifacts use the isolated temporary object prefix', () {
    final artifacts = normalizeWorkflowArtifacts(
      [
        {
          'path': 'workspaces/workspace-1/ghost/request-123/output/image.png',
          'contentType': 'image/png',
          'sizeBytes': 2048,
          'sha256': List.filled(64, 'd').join(),
          'generation': '1730000000000002',
        },
      ],
      workspaceId: 'workspace-1',
      requestId: 'request-123',
      ghostMode: true,
    );

    expect(artifacts.single['path'], contains('/ghost/request-123/'));
    expect(
      () => normalizeWorkflowArtifacts(
        [
          {
            'path': 'workspaces/workspace-1/runs/request-123/output/image.png',
            'contentType': 'image/png',
            'sizeBytes': 2048,
            'sha256': List.filled(64, 'd').join(),
            'generation': '1730000000000002',
          },
        ],
        workspaceId: 'workspace-1',
        requestId: 'request-123',
        ghostMode: true,
      ),
      throwsA(isA<ApiError>()),
    );
  });

  group('poster artifacts', () {
    const prefix = 'workspaces/workspace-1/runs/request-123/';
    List<Map<String, Object?>> normalize(List<Object?> artifacts) =>
        normalizeWorkflowArtifacts(
          artifacts,
          workspaceId: 'workspace-1',
          requestId: 'request-123',
        );

    Map<String, Object?> video() => {
      'path': '${prefix}clip.mp4',
      'contentType': 'video/mp4',
      'sizeBytes': 4096,
      'sha256': List.filled(64, 'a').join(),
      'generation': '1730000000000000',
    };
    Map<String, Object?> poster({String? depicts}) => {
      'path': '${prefix}clip-poster.png',
      'contentType': 'image/png',
      'sizeBytes': 512,
      'sha256': List.filled(64, 'b').join(),
      'generation': '1730000000000001',
      'role': 'poster',
      'posterFor': ?depicts,
    };

    test('carries the relationship through to storage', () {
      final artifacts = normalize([
        video(),
        poster(depicts: '${prefix}clip.mp4'),
      ]);

      expect(artifacts.first.containsKey('role'), isFalse);
      expect(artifacts.last['role'], 'poster');
      expect(artifacts.last['poster_for'], '${prefix}clip.mp4');
    });

    test('a poster must depict an artifact from the same run', () {
      // Otherwise the browser would later ask for a read URL on a path this
      // request never proved.
      expect(
        () => normalize([
          video(),
          poster(depicts: 'workspaces/workspace-1/runs/other/clip.mp4'),
        ]),
        throwsA(isA<ApiError>()),
      );
    });

    test('a poster may not depict itself or another poster', () {
      expect(
        () => normalize([poster(depicts: '${prefix}clip-poster.png')]),
        throwsA(isA<ApiError>()),
      );
    });

    test('role and posterFor may only appear together', () {
      expect(() => normalize([video(), poster()]), throwsA(isA<ApiError>()));
      expect(
        () => normalize([
          video(),
          {...poster(depicts: '${prefix}clip.mp4')}..remove('role'),
        ]),
        throwsA(isA<ApiError>()),
      );
    });

    test('a poster has to be an image', () {
      expect(
        () => normalize([
          video(),
          {...poster(depicts: '${prefix}clip.mp4'), 'contentType': 'video/mp4'},
        ]),
        throwsA(isA<ApiError>()),
      );
    });

    test('an unknown role is refused rather than ignored', () {
      expect(
        () => normalize([
          {...video(), 'role': 'sidecar', 'posterFor': '${prefix}clip.mp4'},
        ]),
        throwsA(isA<ApiError>()),
      );
    });
  });
}

final class _FakeArtifactStorageResolver
    implements ArtifactStorageGatewayResolver {
  _FakeArtifactStorageResolver(this.gateway);

  final ArtifactStorageGateway gateway;
  final List<({String workspaceId, String permission})> requests = [];

  @override
  Future<ArtifactStorageGateway> resolve(
    String workspaceId, {
    required String permission,
  }) async {
    requests.add((workspaceId: workspaceId, permission: permission));
    return gateway;
  }
}

final class _FakeArtifactStorageGateway implements ArtifactStorageGateway {
  _FakeArtifactStorageGateway({this.sizeBytes = 2048});

  final int sizeBytes;
  final List<ArtifactObjectLocator> lookups = [];

  @override
  bool get verifiesRemoteObjects => true;

  @override
  Future<ArtifactUploadContract> createUploadContract() async =>
      const ArtifactUploadContract(
        provider: 'test_provider',
        fields: {'container': 'media'},
      );

  @override
  Future<List<ArtifactObjectMetadata>> readMetadata(
    List<ArtifactObjectLocator> objects,
  ) async {
    lookups.addAll(objects);
    return [
      for (final object in objects)
        ArtifactObjectMetadata(
          version: object.version,
          sizeBytes: sizeBytes,
          contentType: 'image/png',
          sha256: List.filled(64, 'a').join(),
          crc32c: 'crc32c-value',
        ),
    ];
  }
}

final _reportedArtifact = <String, Object?>{
  'path': 'workspaces/workspace-1/runs/request-123/output/image.png',
  'contentType': 'image/png',
  'sizeBytes': 2048,
  'sha256': List.filled(64, 'a').join(),
  'generation': '1730000000000000',
};
