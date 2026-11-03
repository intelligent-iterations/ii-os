import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/view_models/jobs_view_model.dart';

final class _FakeJobRepository implements JobRepository {
  _FakeJobRepository({this.onList});

  Future<JobListing> Function(int call)? onList;
  int calls = 0;

  @override
  Future<JobListing> list(String workspaceId) async {
    calls++;
    final handler = onList;
    if (handler != null) return handler(calls);
    return const JobListing(jobs: [], stale: false);
  }

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => const {};

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async =>
      const {};
}

JobListing _listing(int count, {bool stale = false}) => JobListing(
  jobs: [
    for (var i = 0; i < count; i++) <String, Object?>{'jobId': 'job-$i'},
  ],
  stale: stale,
);

void main() {
  test('Ghost job bodies omit durable notification routing', () {
    final body = const JobSubmission(
      workflowKey: 'acme/media#image-create',
      pageSlug: 'images',
      input: {'prompt': 'private draft'},
      ghostMode: true,
    ).body('workspace-1');

    expect(body['ghostMode'], isTrue);
    expect(body.containsKey('notificationDeepLink'), isFalse);
    expect(body['input'], {'prompt': 'private draft'});
  });

  group('parseJobListing', () {
    test('reads jobs and the stale flag', () {
      final listing = parseJobListing(const {
        'jobs': [
          {'jobId': 'a'},
          {'jobId': 'b'},
        ],
        'stale': true,
      });

      expect(listing.jobs.length, 2);
      expect(listing.stale, isTrue);
    });

    test('degrades to empty rather than throwing on a malformed payload', () {
      // A cast here would throw a TypeError, which reaches the operator as an
      // unexplained red screen instead of an empty list.
      final listing = parseJobListing(const {'jobs': 'not-a-list'});

      expect(listing.jobs, isEmpty);
      expect(listing.stale, isFalse);
    });

    test('treats a missing stale flag as not stale', () {
      expect(parseJobListing(const {'jobs': []}).stale, isFalse);
    });
  });

  group('JobsViewModel', () {
    test('loads and exposes the listing', () async {
      final repository = _FakeJobRepository(
        onList: (_) async => _listing(3, stale: true),
      );
      final model = JobsViewModel(jobs: repository, workspaceId: 'w1');

      await model.load();

      expect(model.jobs.length, 3);
      expect(model.stale, isTrue);
      expect(model.errorMessage, isNull);
      expect(model.isBusy, isFalse);
    });

    test(
      'shows the loading surface only while there is nothing to show',
      () async {
        final repository = _FakeJobRepository(onList: (_) async => _listing(2));
        final model = JobsViewModel(jobs: repository, workspaceId: 'w1');
        expect(model.showLoadingSurface, isFalse, reason: 'not started');

        await model.load();

        // Rule 8: a refresh must never blank a list already on screen, so this
        // is gated on the data being empty rather than on busy alone.
        expect(model.jobs, isNotEmpty);
        expect(model.showLoadingSurface, isFalse);
      },
    );

    test('reports a failure on an explicit load', () async {
      final repository = _FakeJobRepository(
        onList: (_) async => throw StateError('control plane down'),
      );
      final model = JobsViewModel(jobs: repository, workspaceId: 'w1');

      await model.load();

      expect(model.errorMessage, contains('control plane down'));
      expect(model.isBusy, isFalse);
    });

    test(
      'a quiet poll keeps the list and swallows a transient failure',
      () async {
        final repository = _FakeJobRepository(
          onList: (call) async =>
              call == 1 ? _listing(2) : throw StateError('blip'),
        );
        final model = JobsViewModel(jobs: repository, workspaceId: 'w1');
        await model.load();

        await model.load(quiet: true);

        // Surfacing every polling blip would replace
        // a good list with an error nobody asked for.
        expect(model.jobs.length, 2);
        expect(model.errorMessage, isNull);
      },
    );

    test('a successful poll clears an earlier failure', () async {
      final repository = _FakeJobRepository(
        onList: (call) async =>
            call == 1 ? throw StateError('down') : _listing(1),
      );
      final model = JobsViewModel(jobs: repository, workspaceId: 'w1');
      await model.load();
      expect(model.errorMessage, isNotNull);

      await model.load(quiet: true);

      expect(model.errorMessage, isNull);
      expect(model.jobs.length, 1);
    });

    test('start loads once and never polls in the background', () async {
      final repository = _FakeJobRepository(onList: (_) async => _listing(1));
      const interval = Duration(milliseconds: 10);
      final model = JobsViewModel(jobs: repository, workspaceId: 'w1');
      await model.start();
      final afterStart = repository.calls;

      await Future<void>.delayed(interval * 2);

      expect(
        repository.calls,
        afterStart,
        reason: 'start created a read timer',
      );
      model.dispose();
    });
  });
}
