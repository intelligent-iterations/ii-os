# ii-os front-end composition

The binding rules are listed in [Rules](#rules) below. The rest of this
document is the *how*: why each rule exists, the layering it produces, and
worked examples you can copy. Read this before a UI change; do not paste it into
an agent prompt.

## Rules

These numbered rules are binding for every change under `lib/` (rules 17-24
also cover `functions/lib/`). Rule 0 is a discipline; rules 1-16, 19, and 21
are mechanically checked by `dart run tool/audit_frontend.dart`; the rest are
review rules. The sections after this one explain why each rule exists and how
to follow it.

### Front-end composition (rules 0-16)

0. Write the test first. A test written after the code encodes what the code
   does; a test written first encodes what it should do, and the difference is
   invisible once both are green. Every fix starts with a test that reproduces
   the defect and fails for the stated reason -- a test that has never been seen
   red has not been shown to test anything. Before opening a pull request,
   rebase onto the target branch and run `tool/public_quality_gate.sh`; run
   `flutter test --tags golden` as well when the change touches UI.

1. Pages compose, they do not fetch. A file in `lib/screens/` holds layout,
   spacing, and widget composition only: no `api.` call, no JSON parsing, no
   `Timer`, no repository field, and no `setState` carrying server state.
2. One page, one ViewModel. Every routed page is a `ViewModelBuilder` over a
   `BaseViewModel` in `lib/view_models/`. Fetch, mutate, busy, error, polling,
   and selection state live in the ViewModel, and each one has a unit test.
3. All data access goes through `lib/repositories/`. Any `api.` use outside
   `lib/repositories/` is a violation; repositories return typed models, never
   raw `JsonMap`, and own their own parse and failure mapping.
4. Compose with widgets, not methods. `Widget _buildFoo()` helpers are a
   violation -- extract a named `StatelessWidget` with a `const` constructor.
   Default to `StatelessWidget`; use `StatefulWidget` only for a controller,
   animation, or focus node it personally owns.
5. Widgets are shared, not forked. Reusable widgets live in `lib/widgets/`, stay
   under 150 lines, and take plain data plus callbacks -- never `AppController`
   and never a ViewModel. Never copy an existing shared widget into a private
   variant; extend the shared one.
6. Tokens only. Use `IiOsSpacing`, `IiOsRadii`, `IiOsBreakpoints`, and
   `Theme.of(context).textTheme`. Colour comes from `IiOsPalette.of(context)`,
   never from `IiOsColors` -- see rule 13. Outside `lib/theme/`, a raw numeric
   padding, gap, radius, or breakpoint literal and an inline `TextStyle(` are
   violations.
7. Size limits. Every file under 400 lines with a 600 hard cap, and every
   `build()` under 80 lines.
8. State surfaces are shared. Loading, empty, and error render through the
   shared surfaces in `lib/widgets/`, and a refresh never blanks content that is
   already on screen -- gate the spinner on the data being empty, not on busy.
9. Every interactive element carries a semantic label or a tooltip.
10. Any new or changed shared widget ships with a golden test.
11. Components belong to the design system. `packages/ii_os_design_system` is
    where UI lives; `lib/widgets/` is a staging area, not a home. A widget there
    that depends only on Flutter, Lucide, and the design system is portable and
    counts as a violation until it moves.
12. Write for the person, not the auditor. A string authored for verification,
    audit, logging, or a check's `label`, `detail`, or `guidance` is not
    product copy. It may render only inside a collapsed technical disclosure
    that says so; everywhere else a check is named by an id-keyed copy table
    next to the widget, and a check with no sentence written for a person does
    not render on a primary surface at all -- it stays in the disclosure and its
    count stays with it. Name what the user owns -- their repository, their
    GitHub App, their OpenAI account -- never the mechanism behind it: no lease,
    cleanup proof, capability binding, installer version, or branch lineage in
    a sentence a customer reads. One surface states one action and one outcome:
    never list as user tasks the checks a single button is about to satisfy,
    and never show two progress counts with different denominators. An action
    the viewer's role cannot perform is disabled with the reason rendered
    beside the control and a named way to get unblocked -- never enabled and
    then refused by a snackbar.
13. Colour comes from context. `IiOsColors.ink` is a `static const`, so it has
    one value; the product has two modes. Naming one in a widget renders a
    fixed light colour in dark mode -- it looks right in review, it is wrong on
    screen, and no analyzer error catches it. Read
    `IiOsPalette.of(context).brand.text` and its neighbours instead. Each hue
    has three tiers: `container` for a tinted surface, `text` for words and
    small icons, and `fill` for gradients, arcs, and glyphs. `fill` carries no
    contrast duty, so it never has words on it and is never the only carrier
    of meaning.
14. Never read `Theme.of(context).colorScheme`. It is Material's palette, not
    ours: roughly thirty roles nobody chose and `contrast_test` never walks.
15. A widget the design system barrel exports has a section in `example/`. The
    gallery is the acceptance surface, and it renders both modes and three
    widths -- a primitive proven in neither is a primitive nobody has reviewed.
16. The design system depends on Flutter and Lucide, and on nothing else. A
    dependency is the one thing that drags product logic across the boundary
    without anyone noticing.

### Runtime robustness (rules 17-24)

Rules 1-16 govern where code lives. These govern how it behaves before it knows
the answer: the code sits in the right file, the suite is green, and the screen
can still state something untrue. Each review rule carries a note naming what a
check would have to match, so it can graduate into
`tool/frontend_audit_rules.dart`.

17. Unknown is a state, and it never renders as a value. Anything fetched has
    three states, not two: unknown, known-and-empty, and known. A count, a
    badge, a status pill, or a verdict must never show a number or a conclusion
    it does not have yet. `Pending 0` before the first response is not a
    placeholder, it is a false statement, and it is worse than a spinner
    because nothing marks it provisional: a board that renders zeroed lanes
    until a slow response arrives tells anyone who glances at it that there is
    nothing to do. A failed check is unknown, not healthy: swallowing the error
    and returning `null` so the caller shows nothing hides the failure instead
    of naming it. Where two sources describe one subject,
    the surface reconciles them into a single verdict, never a green
    `Live verified` badge beside a sentence saying that subject could not be
    verified.
    *A check would match a count, pill, or badge built from a nullable model
    field with no branch for the null case.*

18. A read on the critical path is concurrent, budgeted, and cached. Fan out
    with `Future.wait`; a `load()` that chains calls which do not depend on
    each other is a defect, and so is an `await` inside a loop over resources.
    Give every page a first-paint budget and keep anything that cannot meet it
    off the critical path -- render the page, then fill it in. Anything calling
    a third party caches its result under an explicit TTL. A page that awaits
    three independent calls in sequence pays the sum of their latencies, and
    one that makes a serial third-party round trip per repository inside a
    loop, uncached, pays that cost again on every load.
    *No check here yet, deliberately: sequential independent awaits are the
    common shape, and a rule that only caught awaits inside loops would miss
    it.*

19. Behaviour must be reachable from a test without pumping a widget. A method
    that mutates server state, decides an outcome, or maps a failure belongs on
    a public class a test can construct -- a ViewModel or a repository -- and it
    ships with a test. Never hang it off a private `State`. Splitting a long
    screen across `part` files is fine and rule 7 asks for it; what this
    forbids is putting behaviour in the extension that does the splitting.
    An extension on a private screen `State` that merges pull requests, deletes
    tickets, or writes status is reachable only by rendering the whole screen;
    if the only test that renders it is a golden, and goldens do not run in CI,
    that action surface has zero executed assertions while every suite reports
    green.

20. A test that cannot fail the way production fails is not coverage. Assert
    against the shape the caller actually receives, not the shape the producer
    happens to hold. A unit test that inspects a thrown Dart object's `code`
    field passes even when the API serialises errors nested under `error`, so a
    client reading the wrong key fails in production behind a green suite. A
    view-model test that constructs `lineId: 'line-1'` proves nothing when the
    router cannot produce an id at all. Rule 0 asks for a test that has been seen red; this asks that it went
    red for the reason it claims to catch.

21. Errors are mapped, never interpolated. `'$error'` and `error.toString()`
    are not product copy. A repository maps a failure onto a typed result that
    names the cause, and the surface renders a sentence written for a person
    plus a way forward. `'Permission profiles could not be verified: $error'`
    concatenates a backend exception onto a primary surface, and it renders
    directly beside a badge claiming the same subject is verified. A snackbar
    carrying a stack-trace string is the same defect with a shorter lifetime. A
    developer-facing `debugPrint` is not this, and the check knows the
    difference.

22. Durable navigation state round-trips, and a test proves it. The operational
    rules already require the URL to carry workspace, screen, resource, tab and
    filter; this is how you know it does. Every page that carries a resource id
    or a filter has a test asserting that building a location and parsing it
    back yields the same state. Adding a page to the router without an entry in
    the table of pages allowed to carry an item costs nothing at compile time
    and silently drops the id: every item link then opens a page saying the
    item is not available, and nothing highlights in the navigation, because
    the page is missing from that set.
    *A check would compare the router's page enum against that table and
    require a round-trip test per page that carries an item.*

23. Work that outlives the screen resumes from the server. A generation, an
    upload, or an agent run is not client state. Persist its id on the resource
    it belongs to, and re-derive the in-flight state on load, so navigation and
    refresh restore it rather than losing it. An in-memory field is a promise
    the app breaks the moment the user clicks away. A screen that re-arms its
    watcher from a persisted job id survives both navigation and refresh; one
    that holds the pending job in a plain field drops the loading tile on the
    first navigation, which is the in-place media loading rule failing one
    layer down.

24. A name owned by another system is validated, not assumed. Project column
    names, workflow filenames, field ids and environment names belong to GitHub
    or GCP, not to this repository. Declare each set in one place and validate
    it against what that system actually reports, failing with a named error
    when they disagree. Comparing free text with `==` inside a state machine
    means someone renaming a column in a UI outside this repo silently makes
    every ticket unqueueable and every human transition return 409 -- and the
    message the user gets tells them to use the ticket's next action, which the
    same rename has already broken.

### Product rules referenced above

Rules 22 and 23 build on two product rules:

- **Canonical URLs.** All durable web navigation state must be represented by a
  canonical `go_router` URL so direct links, sharing, refresh, and browser
  back/forward restore the same workspace, screen, resource, tab, and filter.
  Keep secrets and unsaved form, prompt, upload, and dialog state out of URLs.
- **In-place media loading.** Every asynchronous image or video generation must
  immediately create an in-place media loading state and keep a completion
  listener active until the artifact or terminal error replaces it without
  manual refresh.

## Why these rules exist

An audit of `lib/` found the same defect repeated at every layer, all of
it traceable to pages owning work that is not layout:

| Symptom | Measured |
| --- | --- |
| Direct `api.*` calls in screens and widgets | 69 across 22 files, against 2 repositories |
| Copies of the same workflow-template fetch | 5 `_loadTemplates()`, 4 `_selectedTemplate` getters, 2 forked "unavailable" widgets |
| Ad-hoc loading flags | 30 files, 5 independent `Timer.periodic` pollers |
| Inline `TextStyle` fighting Material defaults | 85, nearly all carrying `letterSpacing: 0` |
| Distinct hardcoded spacing / radius / breakpoint values | 20 / 12 / 17 |
| Files over the 400-line guideline | 30, of which 6 exceed the 600 hard cap |

None of that is a bug in isolation. Together it means no one can change the
aesthetics of ii-os in one place, and every new screen re-derives decisions that
should already be settled.

## The layering

```
lib/screens/       layout + composition only          <- rule 1, 7
lib/widgets/       reusable, data-in / callbacks-out  <- rule 4, 5, 8, 9, 10
lib/view_models/   busy, error, polling, selection    <- rule 2
lib/repositories/  api access, parsing, typed models  <- rule 3
lib/theme/         the only place numbers live        <- rule 6
```

Each arrow points one way. A screen may know its ViewModel; a ViewModel may know
its repositories; a repository knows `ApiClient`. Nothing points back up, and a
shared widget knows none of them -- it takes values and callbacks so it can be
reused, previewed, and golden-tested in isolation.

## Worked example

### Before -- the pattern the audit found

```dart
class GenerateScreen extends StatefulWidget { ... }

class _GenerateScreenState extends State<GenerateScreen> {
  bool _loadingTemplates = true;
  List<WorkflowTemplateModel> _templates = const [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();                       // rule 1: page fetches
  }

  Future<void> _loadTemplates() async {
    final response = await widget.controller.api.get(   // rule 3: no repository
      'v1/workspaces/${widget.controller.workspace!.id}/workflow-templates',
    );
    ...                                     // parsing duplicated in 5 files
    if (mounted) setState(() => _loadingTemplates = false);
  }

  Widget _buildRatioField() { ... }         // rule 4: method, not widget
}
```

### After

`lib/repositories/workflow_template_repository.dart` -- one owner of the
endpoint. An `abstract interface class` plus an `ApiRepository` implementation,
matching `CharacterRepository`, because `ApiClient` is `final` and cannot be
implemented in a test:

```dart
abstract interface class WorkflowTemplateRepository {
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  });
}

final class WorkflowTemplateApiRepository implements WorkflowTemplateRepository {
  const WorkflowTemplateApiRepository(this.api);

  final ApiClient api;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async {
    final response = await api.get('v1/workspaces/$workspaceId/workflow-templates');
    return parseWorkflowTemplates(response, workflowIdPrefix: workflowIdPrefix);
  }
}
```

Keep the wire-format parse in a top-level function like
`parseWorkflowTemplates`. The request needs a signed-in Firebase user and so
cannot run in a unit test; the parse is where the bugs live and it tests
directly against a recorded payload.

`lib/view_models/generate_view_model.dart` -- constructor-injected so it is
testable without a widget tree:

```dart
final class GenerateViewModel extends BaseViewModel {
  GenerateViewModel({
    required WorkflowTemplateRepository templates,
    required JobRepository jobs,
    required this.workspaceId,
  }) : _templates = templates, _jobs = jobs;

  final WorkflowTemplateRepository _templates;
  final JobRepository _jobs;
  final String workspaceId;

  List<WorkflowTemplateModel> templates = const [];
  WorkflowTemplateModel? selected;
  JobModel? submitted;

  Future<void> load() async {
    templates = await runBusyFuture(
      _templates.list(workspaceId, workflowIdPrefix: 'image-create'),
      busyObject: templates,
    );
    selected = templates.firstWhereOrNull((t) => t.enabled) ?? templates.firstOrNull;
    notifyListeners();
  }

  Future<void> submit(ImageGenerationRequest request) async {
    submitted = await runBusyFuture(_jobs.submitImage(workspaceId, request));
    notifyListeners();
  }
}
```

`lib/screens/generate_screen.dart` -- layout and composition, nothing else:

```dart
class GenerateScreen extends StatelessWidget {
  const GenerateScreen({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<GenerateViewModel>.reactive(
      viewModelBuilder: () => GenerateViewModel(...),
      onViewModelReady: (viewModel) => viewModel.load(),
      builder: (context, viewModel, _) => PageFrame(
        title: 'Image generation',
        subtitle: 'Workspace GitHub workflows',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkflowTemplatePicker(          // shared, reused by 5 screens
              templates: viewModel.templates,
              selected: viewModel.selected,
              onSelected: viewModel.select,
            ),
            IiOsGap.md,
            ImagePromptCard(                 // named widget, const constructor
              enabled: !viewModel.isBusy,
              onSubmit: viewModel.submit,
            ),
            IiOsGap.md,
            GenerationResultSurface(
              busy: viewModel.isBusy,
              job: viewModel.submitted,
            ),
          ],
        ),
      ),
    );
  }
}
```

The screen now reads top-to-bottom as the visual hierarchy. That is the test for
rule 1: if you cannot see the layout by skimming `build()`, the page is doing
someone else's job.

## Composition rules in practice

**Widgets, not methods (rule 4).** `Widget _buildHeader()` cannot be `const`,
cannot be reused, cannot be golden-tested, and rebuilds whenever the enclosing
page rebuilds because it has no independent element. A named widget with a
`const` constructor gets all four for free. There is no size at which a
`_build*` helper becomes the right answer.

**Data in, callbacks out (rule 5).** A widget that takes `AppController` or a
ViewModel is welded to this app's state graph. Take the two strings and the
`VoidCallback` it actually needs. This is what lets one `WorkflowTemplatePicker`
serve the image, video, song, storyboard, and image-edit screens instead of five
near-identical private copies.

**Const everything you can.** `const` constructors let Flutter skip both rebuild
and re-layout for unchanged subtrees. Combined with rule 4 this is most of the
performance story for a console this size.

**Keys carry identity, not parameters.** A `ValueKey` that includes a selected
item id forces a remount and a refetch every time selection changes. Key on
what makes the widget a *different thing* (the workspace), and handle the rest
in `didUpdateWidget`.

## Tokens (rule 6)

| Token | Use |
| --- | --- |
| `IiOsSpacing.xs ... xxl` | padding, insets, gaps |
| `IiOsGap.*` | pre-built `SizedBox` gaps in a `Column`/`Row` |
| `IiOsRadii.*` | every corner radius |
| `IiOsBreakpoints.*` | every responsive threshold |
| `IiOsPalette.of(context)` | every colour, in light and dark mode (rule 13) |
| `Theme.of(context).textTheme.*` | every piece of text |

The `TextTheme` defines all slots the app uses, so a bare
`Theme.of(context).textTheme.titleLarge` is already correct -- brand font, brand
colour, brand tracking. If you find yourself writing `letterSpacing: 0`, the
slot you want is missing from the theme; add it there rather than patching the
call site.

## Loading, empty, error (rule 8)

Three states, three shared surfaces, one ordering rule:

```dart
if (viewModel.isBusy && viewModel.items.isEmpty) return const LoadingSurface();
if (viewModel.hasError && viewModel.items.isEmpty) {
  return ErrorSurface(message: ..., onRetry: viewModel.load);
}
if (viewModel.items.isEmpty) return const EmptyState(...);
return ItemList(items: viewModel.items);          // stays visible while refreshing
```

`&& items.isEmpty` is the whole point. A refresh must never replace content the
user is already reading; show progress in the app bar or an inline strip
instead. For generated media the in-place media loading rule in [Rules](#rules)
applies: the spinner belongs in the surface where the artifact will appear, not
only on the button that started it.

Ghost-mode Playground results use a stricter client lifetime. Their signed URL
and verified bytes bypass application caches, the full artifact stays only in
the mounted result widget, and the output surface exposes a local Download
action. Leaving or closing the browser tab can discard that sole in-memory
copy, so the enabled-state copy must say to keep the tab open and download the
result. The control plane removes the workspace object only after those bytes
have passed integrity verification in the browser.

## Testing

**ViewModel unit test** -- no widget tree, no pumping:

```dart
test('load selects the first enabled template', () async {
  final viewModel = GenerateViewModel(
    templates: FakeWorkflowTemplateRepository([disabled, enabled]),
    jobs: FakeJobRepository(),
    workspaceId: 'ws_test',
  );
  await viewModel.load();
  expect(viewModel.selected, enabled);
  expect(viewModel.isBusy, isFalse);
});
```

Repository fakes implement the repository interface against recorded payloads;
they stand in for the network, never for the logic under test.

**Golden test** -- required for any new or changed shared widget:

```dart
testWidgets('StatusPill renders each status colour', (tester) async {
  await tester.pumpWidget(goldenHarness(const StatusPill('running')));
  await expectLater(
    find.byType(StatusPill),
    matchesGoldenFile('goldens/status_pill_running.png'),
  );
});
```

`goldenHarness` wraps the widget in `MaterialApp(theme: IiOsTheme.light())` at a
fixed size so a golden captures the design system, not the ambient defaults.

## Running the audit

```bash
dart run tool/audit_frontend.dart               # human report
dart run tool/audit_frontend.dart --verbose     # every violation, not the first five
dart run tool/audit_frontend.dart --rule R6     # one rule
dart run tool/audit_frontend.dart --ci          # non-zero exit on regression
dart run tool/audit_frontend.dart --update-baseline
```

The script reports per-rule violations with `file:line` and compares the counts
against `tool/frontend_audit_baseline.json`.

The baseline is a ratchet, not a licence. These rules landed against a codebase
that predates them, so a hard zero would have meant either a 20,000-line
unreviewable PR or rules nobody could merge against. Instead the baseline
records the debt that existed on the day the rules landed, CI fails when any
number goes **up**, and every fix lowers a number. Lower the baseline in the
same PR that earns it:

```bash
dart run tool/audit_frontend.dart --update-baseline
```

Raising a baseline number is a review conversation, not a routine edit. The
`--ci` audit runs in `.github/workflows/quality.yml`, so drift fails the build
rather than accumulating.

## The design system adoption loop (rule 11)

The target state is that every reusable component lives in
`packages/ii_os_design_system` and appears in its `example/` gallery. `lib/widgets/`
is a staging area on the way there, not a destination.

Getting there happens one surface at a time. When you touch a screen, run this
loop rather than rewriting the app:

**1. Review what is in the build.**

```bash
dart run tool/audit_frontend.dart --verbose --rule R11   # already portable
dart run tool/audit_frontend.dart --verbose              # everything else
```

R11 lists widgets in `lib/widgets/` that already import nothing but Flutter,
Lucide, and the design system. Those are finished components sitting in the
wrong repository -- moving one is a file move and an export, nothing more.

**2. Replace loose UI with what already exists.**

A raw gap becomes a token. A hand-rolled spinner becomes the shared primitive. A
bespoke empty state becomes `EmptyState`. Never fork a component the package
already has: extend the shared one, because a fork is how two things that were
meant to look identical stop looking identical.

**3. If the component does not exist, author it in the package first.**

Add it to `packages/ii_os_design_system`, give it a gallery section and a test,
*then* point the screen at it. The gallery is the acceptance surface. A
component nobody can see there is a component the next person will rebuild by
hand, which is how the duplication started.

### What blocks a move

Do not drag app dependencies into the package. A widget that needs
`AppController`, a model, or a repository is not "not portable yet" -- its
signature is wrong. Change it to take plain data and callbacks, then move it.

Measured across the 58 widgets in `lib/widgets/`, the two dominant blockers are
`AppController` coupling (18 files, itself a rule 5 violation) and the
`lib/widgets/common.dart` grab-bag (18 files). Splitting those two unblocks most
of the rest, so they are the highest-leverage work -- not the widgets themselves.

R11's count is the distance to the target. Unlike the other baselines it is
meant to be driven to zero, not held flat.

## Behaviour under uncertainty (rules 17-24)

Rules 1-16 ask where code lives. These ask what it does in the seconds before
its data arrives, and whether a test can reach it at all. Two of them the audit
checks; the rest are review rules with the same standing.

### Three states, not two (rule 17)

A nullable model plus `??` is how a screen ends up asserting something false.

```dart
// Before -- a claim, not a placeholder. Renders "0" until the fetch lands.
Text('Pending ${board?.pending.length ?? 0}')

// After -- the count exists, or it does not.
switch (board) {
  null => const IiOsPendingChip(),          // unknown: no number
  final b => Text('Pending ${b.pending.length}'),
}
```

The same applies to a verdict. A check that failed is unknown, not healthy:

```dart
// Before -- the caller cannot tell "passed" from "we never found out".
Future<ReadinessModel?> readiness(String id) async {
  try {
    return ReadinessModel.fromJson(await _api.get(...));
  } on Object {
    return null;                   // looks identical to "nothing to report"
  }
}

// After -- three outcomes, and the surface can say which.
Future<Result<ReadinessModel>> readiness(String id) async {
  try {
    return Ok(ReadinessModel.fromJson(await _api.get(...)));
  } on ApiFailure catch (failure) {
    return Unknown(reason: failure.kind);
  }
}
```

When one card draws on two sources, reconcile before rendering. A card that
shows `Live verified` next to "could not be verified" has two verdicts and no
answer; compute the weakest of the two and show that.

### Load concurrently (rule 18)

```dart
// Before -- 2.0s + 0.1s + 11.2s, because each await waits for the last.
final tickets = await _api.get('.../projects');
final profiles = await _api.get('.../agent-permissions');
final readiness = await _api.get('.../agent-readiness');

// After -- one round trip's worth of latency for three calls.
final (tickets, profiles, readiness) = await (
  _api.get('.../projects'),
  _api.get('.../agent-permissions'),
  _api.get('.../agent-readiness'),
).wait;
```

If one of the three is slow and the page does not need it to be useful, do not
put it in the tuple at all -- render, then let it arrive. On the server the same
rule applies to a fan-out over resources: a `for` loop of `await`s over a
workspace's repositories costs one round trip per repository, every load.

### Behaviour a test can reach (rule 19, checked)

```dart
// Before -- unreachable except by pumping the screen.
// lib/screens/software_workshop_screen_actions.dart
extension _SoftwareWorkshopActions on _SoftwareWorkshopScreenState {
  Future<void> _approveAndMergePullRequest(WorkshopTicket ticket) async { ... }
}

// After -- a test constructs the ViewModel and calls the method.
// lib/view_models/workshop_view_model.dart
class WorkshopViewModel extends BaseViewModel {
  WorkshopViewModel(this._repository);
  final WorkshopRepository _repository;

  Future<void> approveAndMerge(WorkshopTicket ticket) async { ... }
}
```

Splitting a 600-line screen across `part` files is encouraged. Put the layout
in the extension and the behaviour in the ViewModel.

### Map the failure (rule 21, checked)

```dart
// Before -- a backend exception becomes the sentence a customer reads.
advisories.add('Permission profiles could not be verified: $error');
setState(() => _error = error.toString());

// After -- the repository names the cause, the surface writes for the reader.
on ApiFailure catch (failure) {
  return Unknown(reason: failure.kind);
}

// lib/screens/...
Text(switch (reason) {
  FailureKind.forbidden => 'Your role cannot read permission profiles. Ask an '
      'owner for the Agent access capability.',
  FailureKind.network => 'Could not reach GitHub. Retry in a moment.',
});
```

`debugPrint` is exempt. It is compiled out of a release build and nobody but us
reads it.

### The four review rules

- **Rule 20** -- before a test is done, make it fail for the reason it claims to
  catch. Assert on the shape the caller receives: a matcher on a thrown object's
  field does not prove the HTTP envelope carries it.
- **Rule 22** -- every page carrying a resource id or filter gets a
  `location -> fromUri -> location` test. Adding a page to the router without an
  entry in the item table compiles cleanly and drops the id.
- **Rule 23** -- persist the job id on the resource and re-derive in-flight state
  in `load()`. `character_detail_screen.dart` is the pattern to copy.
- **Rule 24** -- a name owned by GitHub or GCP gets declared once and validated
  against what that system reports, with a named failure when it drifts.

## PR checklist

Every UI PR body includes this, filled in honestly:

```markdown
### Front-end composition
- [ ] `dart run tool/audit_frontend.dart` passes (paste the summary line)
- [ ] Pages changed contain layout only; fetch/state moved to a ViewModel
- [ ] New data access went through a repository
- [ ] Reusable UI landed in `packages/ii_os_design_system` with a gallery
      section and a test, not in `lib/widgets/`
- [ ] Loading/empty/error use the shared surfaces and do not blank on refresh
- [ ] No raw spacing/radius/breakpoint literals or inline `TextStyle`
- [ ] Nothing renders a count, badge, or verdict it does not have yet
- [ ] Independent calls on the load path run concurrently
- [ ] New behaviour sits on a class a test can construct, and has that test
- [ ] Failures are mapped to typed results; no `$error` in copy
```

A rule you deliberately broke is fine if the PR says which one and why. A rule
you broke silently is the failure mode these rules exist to stop.
