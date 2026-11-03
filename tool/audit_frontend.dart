/// ii-os front-end composition audit.
///
///   dart run tool/audit_frontend.dart              human report
///   dart run tool/audit_frontend.dart --ci         non-zero exit on regression
///   dart run tool/audit_frontend.dart --verbose    list every violation
///   dart run tool/audit_frontend.dart --rule R6    one rule only
///   dart run tool/audit_frontend.dart --update-baseline
///
/// Rules are numbered to match the numbered rules in `docs/ii-os-frontend.md`
/// § Rules. The baseline records known debt so CI fails on *new* drift
/// while the migration lands; every fix should lower a baseline number and no
/// change may raise one.
library;

import 'dart:convert';
import 'dart:io';

import 'frontend_audit_rules.dart';

const _baselinePath = 'tool/frontend_audit_baseline.json';

Future<void> main(List<String> args) async {
  final ci = args.contains('--ci');
  final verbose = args.contains('--verbose');
  final updateBaseline = args.contains('--update-baseline');
  final ruleFilter = _optionValue(args, '--rule');

  final root = Directory.current;
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run from the ii-os package root.');
    exit(2);
  }

  final sources = loadSources(root, 'lib');
  final goldens = _goldenNames(root);
  final routedPages = _routedPages(sources);

  final violations = <Violation>[
    ...checkPagesDoNotFetch(sources),
    ..._checkPagesHaveViewModels(sources, routedPages),
    ...checkApiOnlyInRepositories(sources),
    ...checkNoBuildMethods(sources),
    ...checkWidgetsAreShareable(sources),
    ...checkTokensOnly(sources),
    ...checkSizeLimits(sources),
    ...checkRefreshDoesNotBlank(sources),
    ...checkInteractiveLabels(sources),
    ...checkGoldenCoverage(sources, goldens),
    ...checkPortableWidgets(sources),
    ...checkBackendTextStaysTechnical(sources),
    ...checkColourFromContext(sources),
    ...checkNoMaterialColorScheme(sources),
    ..._checkGalleryCoverage(root),
    ..._checkPackagePurity(root),
    ...checkBehaviourIsTestable(sources),
    ...checkErrorsAreMapped(sources),
  ].where((v) => ruleFilter == null || v.rule == ruleFilter).toList();

  final counts = <String, int>{for (final rule in ruleTitles.keys) rule: 0};
  for (final violation in violations) {
    counts[violation.rule] = (counts[violation.rule] ?? 0) + 1;
  }

  if (updateBaseline) {
    File('${root.path}/$_baselinePath').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(counts)}\n',
    );
    stdout.writeln('Baseline written to $_baselinePath');
    return;
  }

  final baseline = _readBaseline(root);
  final regressions = <String>[];
  final improvements = <String>[];
  for (final rule in ruleTitles.keys) {
    final now = counts[rule] ?? 0;
    final was = baseline[rule];
    if (was == null) continue;
    if (now > was) regressions.add('$rule: $was -> $now');
    if (now < was) improvements.add('$rule: $was -> $now');
  }

  _report(violations, counts, baseline, verbose: verbose);

  if (improvements.isNotEmpty) {
    stdout.writeln('\nImproved since baseline: ${improvements.join(', ')}');
    stdout.writeln('Run with --update-baseline to lock the improvement in.');
  }

  if (regressions.isEmpty) {
    stdout.writeln(
      '\nSUMMARY: ${violations.length} known violations, 0 regressions '
      'against $_baselinePath.',
    );
    return;
  }

  stdout.writeln('\nSUMMARY: ${regressions.length} rule(s) regressed:');
  for (final regression in regressions) {
    stdout.writeln('  $regression');
  }
  if (ci) exit(1);
}

/// R2 -- every routed page must build through a ViewModel.
///
/// Checked by dependency rather than by filename: a ViewModel is named for the
/// domain it models, not for the screen that happens to host it today, and
/// `generate_screen.dart` is legitimately backed by
/// `image_generation_view_model.dart`.
List<Violation> _checkPagesHaveViewModels(
  List<SourceFile> sources,
  Set<String> routedPages,
) {
  final out = <Violation>[];
  final importsViewModel = RegExp(
    r"""import\s+'[^']*view_models/[a-z0-9_]+\.dart'""",
  );
  for (final file in sources.where((f) => routedPages.contains(f.path))) {
    final hasImport = importsViewModel.hasMatch(file.raw);
    final buildsThrough =
        file.code.contains('ViewModelBuilder') ||
        file.code.contains('StackedView');
    if (hasImport && buildsThrough) continue;
    out.add(
      Violation(
        'R2',
        file.path,
        1,
        hasImport
            ? 'routed page does not build through its ViewModel'
            : 'routed page has no ViewModel in lib/view_models/',
      ),
    );
  }
  return out;
}

/// A page is routed when the operator shell imports it.
Set<String> _routedPages(List<SourceFile> sources) {
  final shell = sources.where(
    (f) => f.path == 'lib/screens/operator_shell.dart',
  );
  if (shell.isEmpty) return const {};
  final imports = RegExp(r"""import\s+'([a-z0-9_]+\.dart)'""");
  return {
    for (final match in imports.allMatches(shell.first.raw))
      'lib/screens/${match.group(1)}',
  }.where((path) => sources.any((f) => f.path == path)).toSet();
}

Set<String> _goldenNames(Directory root) {
  final dir = Directory('${root.path}/test');
  if (!dir.existsSync()) return const {};
  final names = <String>{};
  final pattern = RegExp(r"matchesGoldenFile\(\s*'[^']*?([a-z0-9_]+)\.png'");
  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final source = file.readAsStringSync();
    for (final match in pattern.allMatches(source)) {
      names.add(match.group(1)!);
    }
  }
  return names;
}

Map<String, int> _readBaseline(Directory root) {
  final file = File('${root.path}/$_baselinePath');
  if (!file.existsSync()) return const {};
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) return const {};
  return {
    for (final entry in decoded.entries)
      entry.key as String: (entry.value as num).toInt(),
  };
}

void _report(
  List<Violation> violations,
  Map<String, int> counts,
  Map<String, int> baseline, {
  required bool verbose,
}) {
  stdout.writeln('ii-os front-end composition audit\n');
  for (final MapEntry(key: rule, value: title) in ruleTitles.entries) {
    final now = counts[rule] ?? 0;
    final was = baseline[rule];
    final delta = was == null
        ? ''
        : now == was
        ? ' (baseline $was)'
        : now > was
        ? '  REGRESSED from $was'
        : '  improved from $was';
    stdout.writeln('$rule  ${now.toString().padLeft(4)}  $title$delta');
    final items = violations.where((v) => v.rule == rule).toList();
    final shown = verbose ? items : items.take(5).toList();
    for (final violation in shown) {
      stdout.writeln(
        '        ${violation.file}:${violation.line}  ${violation.detail}',
      );
    }
    if (!verbose && items.length > shown.length) {
      stdout.writeln(
        '        ... ${items.length - shown.length} more (--verbose)',
      );
    }
  }
}

String? _optionValue(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

const _designSystem = 'packages/ii_os_design_system';

/// R15 -- a widget the barrel exports has a gallery section.
///
/// The gallery is the acceptance surface: a primitive nobody can see there is
/// a primitive nobody will reuse, and one that never renders in both modes is
/// one whose dark-mode behaviour nobody has looked at.
List<Violation> _checkGalleryCoverage(Directory root) {
  final out = <Violation>[];
  final barrel = File(
    '${root.path}/$_designSystem/lib/ii_os_design_system.dart',
  );
  if (!barrel.existsSync()) return out;

  final gallery = Directory('${root.path}/$_designSystem/example/lib');
  if (!gallery.existsSync()) return out;
  final shown = gallery
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  final exported = RegExp(
    r"export 'src/widgets/([a-z0-9_]+)\.dart';",
  ).allMatches(barrel.readAsStringSync());
  for (final match in exported) {
    final file = File(
      '${root.path}/$_designSystem/lib/src/widgets/${match.group(1)}.dart',
    );
    if (!file.existsSync()) continue;
    final classes = RegExp(r'^class ([A-Z][A-Za-z0-9]*)', multiLine: true)
        .allMatches(file.readAsStringSync())
        .map((m) => m.group(1)!)
        .where((name) => !name.startsWith('_'));
    for (final name in classes) {
      if (shown.contains(name)) continue;
      out.add(
        Violation(
          'R15',
          '$_designSystem/lib/src/widgets/${match.group(1)}.dart',
          1,
          '$name is exported but never rendered in example/',
        ),
      );
    }
  }
  return out;
}

/// R16 -- the design system depends on Flutter and Lucide only.
///
/// A dependency is the one thing that drags product logic across the boundary
/// without anyone noticing, and a package that cannot render in a widget test
/// with no network is already broken.
List<Violation> _checkPackagePurity(Directory root) {
  final out = <Violation>[];
  const allowed = {'flutter', 'lucide_icons_flutter'};
  final pubspec = File('${root.path}/$_designSystem/pubspec.yaml');
  if (!pubspec.existsSync()) return out;

  final lines = pubspec.readAsLinesSync();
  var inDependencies = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith(' ') && line.trim().isNotEmpty) {
      inDependencies = line.startsWith('dependencies:');
      continue;
    }
    if (!inDependencies) continue;
    final match = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
    if (match == null || allowed.contains(match.group(1))) continue;
    out.add(
      Violation(
        'R16',
        '$_designSystem/pubspec.yaml',
        i + 1,
        '${match.group(1)} is not on the design system dependency allowlist',
      ),
    );
  }

  final lib = Directory('${root.path}/$_designSystem/lib');
  if (!lib.existsSync()) return out;
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final source = file.readAsStringSync();
    for (final banned in const ['dart:io', 'dart:html', 'dart:ffi']) {
      if (!source.contains("import '$banned'")) continue;
      out.add(
        Violation(
          'R16',
          file.path.replaceFirst('${root.path}/', ''),
          1,
          'imports $banned; the design system must render with no platform',
        ),
      );
    }
  }
  return out;
}
