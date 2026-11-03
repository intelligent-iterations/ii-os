import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

Widget _host(Widget child, {double width = 800}) {
  return MaterialApp(
    theme: IiOsTheme.light(),
    home: Scaffold(
      body: SizedBox(width: width, child: child),
    ),
  );
}

void main() {
  group('theme', () {
    testWidgets('a selected segment is the same colour as every other '
        'selection', (tester) async {
      // ListTile and Chip already read `brand.container` when selected.
      // SegmentedButton fell through to `secondaryContainer`, so one form
      // could show a violet selection above a green one and mean the same
      // thing by both.
      for (final theme in [IiOsTheme.light(), IiOsTheme.dark()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Loose')),
                  ButtonSegment(value: 1, label: Text('Faithful')),
                ],
                selected: const {0},
                onSelectionChanged: (_) {},
              ),
            ),
          ),
        );

        final context = tester.element(find.byType(SegmentedButton<int>));
        final palette = IiOsPalette.of(context);
        final style = Theme.of(context).segmentedButtonTheme.style!;
        expect(
          style.backgroundColor!.resolve({WidgetState.selected}),
          palette.brand.container,
        );
        expect(
          style.foregroundColor!.resolve({WidgetState.selected}),
          palette.brand.text,
        );
      }
    });
  });

  group('theme typography', () {
    test('a snackbar is set in the brand face, like every other surface', () {
      // The style named a colour and nothing else, so the one surface that
      // only appears when something has gone wrong was also the one surface
      // set in the platform default font.
      for (final theme in [IiOsTheme.light(), IiOsTheme.dark()]) {
        expect(
          theme.snackBarTheme.contentTextStyle?.fontFamily,
          iiOsFontFamily,
        );
      }
    });
  });

  group('LoadingSurface', () {
    testWidgets('announces what is loading without reading it twice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const LoadingSurface(label: 'Loading jobs')),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The label is inside ExcludeSemantics, so the Semantics wrapper is the
      // single announcement rather than the spinner plus a duplicate string.
      expect(
        tester
            .getSemantics(find.byType(LoadingSurface))
            .label
            .contains('Loading jobs'),
        isTrue,
      );
    });

    testWidgets('renders without a label', (tester) async {
      await tester.pumpWidget(_host(const LoadingSurface()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ErrorSurface', () {
    testWidgets('puts recovery in the same place as the content', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        _host(
          ErrorSurface(
            title: 'Could not load',
            message: 'Nothing was changed.',
            onRetry: () => retries++,
          ),
        ),
      );

      expect(find.text('Could not load'), findsOneWidget);
      expect(find.text('Nothing was changed.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('keeps secondary recovery and its disabled reason together', (
      tester,
    ) async {
      var tickets = 0;
      await tester.pumpWidget(
        _host(
          ErrorSurface(
            title: 'Export did not finish',
            message: 'The edit is still available.',
            onRetry: () {},
            retryLabel: 'Retry export',
            secondaryActions: [
              OutlinedButton(
                onPressed: () => tickets++,
                child: const Text('Create healing ticket'),
              ),
            ],
            disabledReason:
                'Ask a workspace editor to create a Software Workshop ticket.',
          ),
        ),
      );

      await tester.tap(find.text('Create healing ticket'));
      expect(tickets, 1);
      expect(
        find.text(
          'Ask a workspace editor to create a Software Workshop ticket.',
        ),
        findsOneWidget,
      );
    });
  });

  group('EmptyState', () {
    testWidgets('shows its action when one is given', (tester) async {
      await tester.pumpWidget(
        _host(
          EmptyState(
            title: 'No characters yet',
            message: 'They will appear here.',
            action: FilledButton(onPressed: () {}, child: const Text('Create')),
          ),
        ),
      );
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('omits the action row when there is none', (tester) async {
      await tester.pumpWidget(
        _host(const EmptyState(title: 'Nothing', message: 'Still nothing.')),
      );
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('KpiCard', () {
    testWidgets('reads label and value as one node', (tester) async {
      await tester.pumpWidget(
        _host(
          KpiCard(
            label: 'Active jobs',
            value: '4',
            hue: IiOsPalette.light.brand,
          ),
        ),
      );
      expect(tester.getSemantics(find.byType(KpiCard)).label, 'Active jobs, 4');
    });

    testWidgets('an absent value is an em dash, not a zero', (tester) async {
      await tester.pumpWidget(
        _host(
          KpiCard(label: 'Spend', value: null, hue: IiOsPalette.light.brand),
        ),
      );
      expect(find.text('\u2014'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(
        tester.getSemantics(find.byType(KpiCard)).label,
        'Spend, no value yet',
      );
    });
  });

  group('ResponsiveFieldPair', () {
    Widget pair() => const ResponsiveFieldPair(
      first: SizedBox(key: ValueKey('first'), height: 10),
      second: SizedBox(key: ValueKey('second'), height: 10),
    );

    testWidgets('shares a row at the paired-fields threshold', (tester) async {
      await tester.pumpWidget(
        _host(pair(), width: IiOsBreakpoints.pairedFields),
      );
      expect(find.byType(Row), findsWidgets);
      final first = tester.getTopLeft(find.byKey(const ValueKey('first')));
      final second = tester.getTopLeft(find.byKey(const ValueKey('second')));
      expect(first.dy, second.dy, reason: 'fields should be side by side');
    });

    testWidgets('stacks one pixel below the threshold', (tester) async {
      await tester.pumpWidget(
        _host(pair(), width: IiOsBreakpoints.pairedFields - 1),
      );
      final first = tester.getTopLeft(find.byKey(const ValueKey('first')));
      final second = tester.getTopLeft(find.byKey(const ValueKey('second')));
      expect(second.dy, greaterThan(first.dy), reason: 'fields should stack');
    });
  });

  group('DurationSelector', () {
    testWidgets('announces and changes a bounded media duration', (
      tester,
    ) async {
      double duration = 15;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => DurationSelector(
              value: duration,
              minimum: 2,
              maximum: 20,
              divisions: 18,
              valueFormatter: (value) => '${value.round()} seconds',
              onChanged: (value) => setState(() => duration = value),
            ),
          ),
        ),
      );

      expect(find.text('15 seconds'), findsOneWidget);
      final semantics = tester.getSemantics(find.byType(DurationSelector));
      expect(semantics.label, 'Duration');
      expect(semantics.value, '15 seconds');
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );

      await tester.drag(find.byType(Slider), const Offset(-200, 0));
      await tester.pump();
      expect(duration, lessThan(15));
    });
  });

  group('RefreshingStrip', () {
    testWidgets('is a live region so a background reload is announced', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const RefreshingStrip()));
      final node = tester.getSemantics(find.byType(RefreshingStrip));
      expect(node.label, contains('Refreshing'));
    });
  });

  group('PromptEnhanceAction', () {
    testWidgets('shows a glow overlay only while the rewrite is running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const PromptEnhanceAction(
            outcome: PromptEnhanceOutcome.running,
            onEnhance: null,
            tooltip: 'Enhance this prompt',
          ),
        ),
      );

      expect(find.byKey(const ValueKey('prompt-enhance-glow')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('prompt-enhance-overlay')),
        findsOneWidget,
      );
    });

    testWidgets('keeps the authors prompting guide beside the rewrite', (
      tester,
    ) async {
      var guideOpens = 0;
      await tester.pumpWidget(
        _host(
          PromptEnhanceAction(
            outcome: PromptEnhanceOutcome.idle,
            onEnhance: () {},
            onOpenGuide: () => guideOpens++,
            tooltip: 'Rewrite this for FLUX.2',
          ),
        ),
      );

      await tester.tap(find.text('Official guide'));

      expect(guideOpens, 1);
    });
  });

  group('IiOsIdentityGlyph', () {
    testWidgets('keeps its identity hue when a ListTile selects it', (
      tester,
    ) async {
      // The regression this widget exists to prevent: ListTile.selectedColor
      // tints its leading icon through IconTheme, so a themed glyph would turn
      // green exactly when the operator is standing in that item.
      await tester.pumpWidget(
        _host(
          const ListTile(
            selected: true,
            selectedColor: IiOsColors.green,
            leading: IiOsIdentityGlyph(
              colorToken: 'violet',
              iconToken: 'rocket',
            ),
            title: Text('Payments'),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, IiOsColors.identityViolet);
      expect(icon.color, isNot(IiOsColors.green));
    });

    testWidgets('falls back rather than throwing on an unknown token', (
      tester,
    ) async {
      // The token comes from a database. A rollback or version skew must
      // degrade to a plain glyph, not a red screen inside someone's sidebar.
      await tester.pumpWidget(
        _host(
          const IiOsIdentityGlyph(
            colorToken: 'chartreuse',
            iconToken: 'unicorn',
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, IiOsIdentity.fallbackColor);
      expect(icon.icon, IiOsIdentity.fallbackIcon);
    });

    testWidgets('marks attention in the warning hue, not the identity one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const IiOsIdentityGlyph(
            colorToken: 'violet',
            iconToken: 'rocket',
            needsAttention: true,
          ),
        ),
      );

      final dot = tester.widget<Container>(find.byType(Container));
      final decoration = dot.decoration! as BoxDecoration;
      expect(decoration.color, IiOsColors.amber);
      expect(decoration.color, isNot(IiOsColors.identityViolet));
    });

    testWidgets('announces its name, since colour and shape cannot', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const IiOsIdentityGlyph(
            colorToken: 'violet',
            iconToken: 'rocket',
            semanticLabel: 'Payments production line',
          ),
        ),
      );

      expect(find.bySemanticsLabel('Payments production line'), findsOneWidget);
    });

    test('every identity token resolves to a contrast-proven swatch', () {
      // IiOsColors.all is what contrast_test.dart iterates, so a hue reachable
      // from a token but absent from that list would ship unproven.
      final proven = {for (final swatch in IiOsColors.all) swatch.color};
      for (final token in IiOsIdentity.colorTokens) {
        expect(
          proven,
          contains(IiOsIdentity.colorFor(token)),
          reason: '$token is not in IiOsColors.all',
        );
      }
      expect(IiOsIdentity.iconTokens, isNotEmpty);
    });
  });

  group('PendingIcon', () {
    testWidgets('keeps the same square in both states', (tester) async {
      await tester.pumpWidget(
        _host(const PendingIcon(icon: Icons.send, pending: false)),
      );
      final idle = tester.getSize(find.byType(PendingIcon));

      await tester.pumpWidget(
        _host(const PendingIcon(icon: Icons.send, pending: true)),
      );
      final busy = tester.getSize(find.byType(PendingIcon));

      // The whole point: a button must not change width when it goes busy.
      expect(busy, idle);
    });

    testWidgets('shows the icon when idle and a spinner when pending', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const PendingIcon(icon: Icons.send, pending: false)),
      );
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(
        _host(const PendingIcon(icon: Icons.send, pending: true)),
      );
      expect(find.byIcon(Icons.send), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('carries its colour into the spinner', (tester) async {
      // A coloured glyph that reverts to the default accent mid-action reads
      // as a different control, so the tint has to survive the state change.
      await tester.pumpWidget(
        _host(
          const PendingIcon(
            icon: Icons.add,
            pending: false,
            color: IiOsColors.green,
          ),
        ),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).color, IiOsColors.green);

      await tester.pumpWidget(
        _host(
          const PendingIcon(
            icon: Icons.add,
            pending: true,
            color: IiOsColors.green,
          ),
        ),
      );
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, IiOsColors.green);
    });

    testWidgets('inherits the ambient icon colour when given none', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const PendingIcon(icon: Icons.add, pending: false)),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).color, isNull);
    });

    testWidgets('announces the pending state', (tester) async {
      await tester.pumpWidget(
        _host(
          const PendingIcon(
            icon: Icons.send,
            pending: true,
            pendingLabel: 'Sending',
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(PendingIcon)).label,
        contains('Sending'),
      );
    });
  });

  group('MediaDownloadButton', () {
    testWidgets('runs one save at a time and announces progress', (
      tester,
    ) async {
      final pending = Completer<void>();
      var saves = 0;
      await tester.pumpWidget(
        _host(
          MediaDownloadButton(
            onPressed: () {
              saves++;
              return pending.future;
            },
          ),
        ),
      );

      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(saves, 1);
      expect(find.text('Saving\u2026'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(MediaDownloadButton)).label,
        contains('Saving download'),
      );

      await tester.tap(find.text('Saving\u2026'));
      expect(saves, 1);
      pending.complete();
      await tester.pump();
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('is disabled when no save callback is available', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const MediaDownloadButton(onPressed: null)),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });
  });

  group('InlineFormError', () {
    testWidgets('occupies nothing when there is no message', (tester) async {
      await tester.pumpWidget(_host(const InlineFormError(message: null)));
      // The host gives a tight width, so only the height can shrink -- and the
      // height is what would push a form's contents down.
      expect(tester.getSize(find.byType(InlineFormError)).height, 0);
    });

    testWidgets('shows the message when there is one', (tester) async {
      await tester.pumpWidget(
        _host(const InlineFormError(message: 'That code has expired.')),
      );
      expect(find.text('That code has expired.'), findsOneWidget);
      expect(
        tester.getSize(find.byType(InlineFormError)).height,
        greaterThan(0),
      );
    });
  });

  group('IiOsMark', () {
    testWidgets('is decorative without a label and an image with one', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const IiOsMark(size: 40)));
      expect(tester.getSemantics(find.byType(IiOsMark)).label, isEmpty);

      await tester.pumpWidget(
        _host(const IiOsMark(size: 40, semanticLabel: 'ii-os')),
      );
      expect(tester.getSemantics(find.byType(IiOsMark)).label, 'ii-os');
    });

    testWidgets('renders at the size it is given', (tester) async {
      await tester.pumpWidget(_host(const Align(child: IiOsMark(size: 64))));
      expect(tester.getSize(find.byType(IiOsMark)), const Size(64, 64));
    });
  });

  group('BackgroundWorkCard', () {
    testWidgets('shows a live indicator while the work is running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          BackgroundWorkCard(
            running: true,
            title: 'Installing\u2026',
            detail: 'This takes a few minutes.',
            onFollow: () {},
            onRetry: () => fail('a running card must not retry'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Installing\u2026'), findsOneWidget);
      expect(find.text('Follow the run'), findsOneWidget);
      expect(find.text('Start it again'), findsNothing);
    });

    testWidgets('stopping the watch is not reported as a failure', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const BackgroundWorkCard(
            running: false,
            title: 'Still not verified',
            detail: 'The run may still finish.',
          ),
        ),
      );

      // No spinner, no follow button, and nothing claiming the work failed.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('Still not verified'), findsOneWidget);
    });

    testWidgets('the stopped state offers a way to start the work again', (
      tester,
    ) async {
      // Without this the stopped state is a dead end: a link into another
      // system and nothing to do here. Runs that queue behind a busy runner,
      // and runs that end for an explicitly retryable reason, both land here.
      var retried = 0;
      await tester.pumpWidget(
        _host(
          BackgroundWorkCard(
            running: false,
            title: 'This is taking longer than usual',
            detail: 'Starting again is safe.',
            onFollow: () {},
            onRetry: () => retried += 1,
            retryLabel: 'Install again',
          ),
        ),
      );

      await tester.tap(find.text('Install again'));
      expect(retried, 1);
      expect(find.text('Follow the run'), findsOneWidget);
    });

    testWidgets('a running card offers no retry', (tester) async {
      // Retrying live work would dispatch a second run against the same
      // approval.
      await tester.pumpWidget(
        _host(
          BackgroundWorkCard(
            running: true,
            title: 'Installing\u2026',
            detail: 'This takes a few minutes.',
            onFollow: () {},
          ),
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('ReviewedCommitGuide', () {
    testWidgets('puts the exact command on the clipboard', (tester) async {
      final copied = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var notified = 0;
      const command = 'git tag marker abc && git push origin marker';
      await tester.pumpWidget(
        _host(
          ReviewedCommitGuide(
            subject: 'acme-co/example-app on dev',
            marker: 'marker',
            command: command,
            onCopied: () => notified++,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Copy the command'));
      await tester.pumpAndSettle();

      expect(copied.single.arguments['text'], command);
      expect(notified, 1);
    });

    testWidgets('degrades to prose when no command is known', (tester) async {
      await tester.pumpWidget(
        _host(
          const ReviewedCommitGuide(
            subject: 'acme-co/example-app on dev',
            marker: '',
            command: '',
          ),
        ),
      );

      expect(find.byTooltip('Copy the command'), findsNothing);
      expect(find.textContaining('acme-co/example-app'), findsOneWidget);
    });
  });

  group('PermissionChangeGuide', () {
    testWidgets('says what each permission is for, not just its value', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const PermissionChangeGuide(
            steps: ['Open permission settings.'],
            changes: [
              PermissionChange(
                name: 'Issues',
                section: 'Repository permissions',
                currentValue: 'No access',
                requiredValue: 'Read and write',
                reason: 'Lets it post progress on the ticket you gave it.',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Issues'), findsOneWidget);
      expect(find.text('Repository permissions'), findsOneWidget);
      expect(find.text('No access'), findsOneWidget);
      expect(find.text('Read and write'), findsOneWidget);
      expect(
        find.text('Lets it post progress on the ticket you gave it.'),
        findsOneWidget,
      );
      // The reason reaches a screen reader on the same node as the change, so
      // the value and its justification are never announced apart.
      final labelled = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label ?? '').contains('Issues'),
      );
      final label = tester.widget<Semantics>(labelled).properties.label;
      expect(label, contains('No access'));
      expect(label, contains('Read and write'));
      expect(label, contains('post progress'));
    });

    testWidgets('a change with no reason still renders its values', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const PermissionChangeGuide(
            steps: [],
            changes: [
              PermissionChange(
                name: 'Actions',
                section: 'Repository permissions',
                currentValue: 'Read-only',
                requiredValue: 'Read and write',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Actions'), findsOneWidget);
      expect(find.text('Then do this'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('scales', () {
    test('icon sizes ascend and stay on even values', () {
      final values = IiOsIconSize.all.map((entry) => entry.$2).toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]));
      }
      // Odd icon sizes are what produced 15/17/19 sitting beside 16/18/20.
      for (final value in values) {
        expect(value % 2, 0, reason: '$value is odd');
      }
    });

    test('content widths ascend', () {
      final values = IiOsWidths.all.map((entry) => entry.$2).toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]));
      }
    });
  });

  group('AppearanceToggle', () {
    Future<void> pump(
      WidgetTester tester,
      Brightness brightness,
      ValueChanged<Brightness> onChanged,
    ) {
      return tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(
            body: AppearanceToggle(
              brightness: brightness,
              onChanged: onChanged,
            ),
          ),
        ),
      );
    }

    testWidgets('offers the mode the viewer is not already in', (tester) async {
      // It takes the resolved Brightness rather than a ThemeMode because under
      // ThemeMode.system the mode alone does not say which the viewer sees.
      await pump(tester, Brightness.light, (_) {});
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).tooltip,
        'Switch to dark mode',
      );

      await pump(tester, Brightness.dark, (_) {});
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).tooltip,
        'Switch to light mode',
      );
    });

    testWidgets('reports the brightness it is switching to', (tester) async {
      final requested = <Brightness>[];
      await pump(tester, Brightness.light, requested.add);
      await tester.tap(find.byKey(const Key('appearance-toggle')));
      expect(requested, [Brightness.dark]);
    });

    testWidgets('carries a semantic label, not just a glyph', (tester) async {
      await pump(tester, Brightness.light, (_) {});
      expect(
        tester.widget<Icon>(find.byType(Icon)).semanticLabel,
        'Switch to dark mode',
      );
    });
  });

  group('IiOsMetaChip', () {
    testWidgets('reads as a fact, not an affordance', (tester) async {
      await tester.pumpWidget(_host(const IiOsMetaChip(label: 'MiniMax H3')));
      expect(find.text('MiniMax H3'), findsOneWidget);
      // A Material Chip would announce as a button and invite a tap that does
      // nothing; this is a boundary around a word.
      expect(find.byType(Chip), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('truncates rather than overflowing its row', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 80,
            child: IiOsMetaChip(label: 'acme-co/example-app'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('IiOsSelectionRail', () {
    testWidgets('marks only the selected entry', (tester) async {
      for (final selected in [true, false]) {
        await tester.pumpWidget(
          _host(
            IiOsSelectionRail(
              selected: selected,
              color: IiOsPalette.light.brand.text,
              child: const SizedBox(height: 44, child: Text('Jobs')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(AnimatedContainer),
          selected ? findsOneWidget : findsNothing,
          reason: 'selected=$selected',
        );
      }
    });

    testWidgets('keeps the rail on the leading edge in RTL', (tester) async {
      // The Directionality has to sit inside the host: a MaterialApp
      // establishes its own, so wrapping the host proves nothing.
      await tester.pumpWidget(
        _host(
          const Directionality(
            textDirection: TextDirection.rtl,
            child: _RailProbe(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rail = tester.getRect(find.byType(AnimatedContainer));
      final whole = tester.getRect(find.byType(IiOsSelectionRail));
      expect(
        rail.right,
        closeTo(whole.right, 1),
        reason: 'the rail must follow the leading edge, not sit left always',
      );
    });
  });

  group('IiOsMediaWell', () {
    testWidgets('is deep in both modes, not tied to the theme', (tester) async {
      // A well that followed the surface colour would go white in light mode,
      // which is the one thing artwork must never sit on.
      final grounds = <Color>[];
      for (final theme in [IiOsTheme.light(), IiOsTheme.dark()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: IiOsMediaWell(child: SizedBox.square(dimension: 10)),
            ),
          ),
        );
        grounds.add(
          tester
              .widget<ColoredBox>(
                find.descendant(
                  of: find.byType(IiOsMediaWell),
                  matching: find.byType(ColoredBox),
                ),
              )
              .color,
        );
      }
      expect(grounds.first, grounds.last);
      expect(grounds.first, IiOsColors.mediaWell);
    });
  });

  group('IiOsChosenTick', () {
    testWidgets('draws the tick on an opaque disc, not over the picture', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(IiOsChosenTick(color: IiOsPalette.light.brand.text)),
      );
      // The disc is what makes it survive a bright edge; without it the tick
      // disappears into whatever the artwork happens to be doing there.
      final decorated = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, IiOsPalette.light.brand.text);
    });
  });

  group('GhostModeControl', () {
    testWidgets('states the enabled consequence and reports the choice', (
      tester,
    ) async {
      final requested = <bool>[];
      await tester.pumpWidget(
        _host(
          GhostModeControl(enabled: true, onChanged: requested.add),
          width: 320,
        ),
      );

      expect(find.text('Ghost mode on'), findsOneWidget);
      expect(find.text('Download before closing this tab'), findsOneWidget);
      await tester.tap(find.byType(Switch));

      expect(requested, [false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('names durable retention while disabled', (tester) async {
      await tester.pumpWidget(
        _host(GhostModeControl(enabled: false, onChanged: (_) {}), width: 320),
      );

      expect(find.text('Ghost mode'), findsOneWidget);
      expect(
        find.text('Save generations to workspace history'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Renders the rail at a known size so its box can be measured.
class _RailProbe extends StatelessWidget {
  const _RailProbe();

  @override
  Widget build(BuildContext context) => IiOsSelectionRail(
    selected: true,
    color: IiOsPalette.light.brand.text,
    child: const SizedBox(width: 200, height: 44),
  );
}
