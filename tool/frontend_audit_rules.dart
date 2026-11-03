/// Rule definitions for the ii-os front-end composition audit.
///
/// Each rule maps to a numbered rule in `docs/ii-os-frontend.md` § Rules.
/// Rules operate on source with comments and string literals blanked out, so a
/// token inside a doc comment or a prompt string never counts as a violation.
library;

import 'dart:io';

final class Violation {
  const Violation(this.rule, this.file, this.line, this.detail);

  final String rule;
  final String file;
  final int line;
  final String detail;

  @override
  String toString() => '$file:$line  $detail';
}

final class SourceFile {
  SourceFile(this.path, this.raw) : code = blankNonCode(raw);

  final String path;
  final String raw;
  final String code;

  late final List<String> codeLines = code.split('\n');
  late final int lineCount = raw.split('\n').length;

  bool get isScreen => path.startsWith('lib/screens/');
  bool get isWidget => path.startsWith('lib/widgets/');
  bool get isRepository => path.startsWith('lib/repositories/');
  bool get isTheme => path.startsWith('lib/theme/');
  bool get isViewModel => path.startsWith('lib/view_models/');
}

/// Replaces comments and string-literal contents with spaces, preserving line
/// numbers and overall length so offsets stay meaningful.
///
/// A `${...}` interpolation is *not* literal text -- it is code that runs, and
/// whatever it evaluates to is rendered. Blanking it would hide real
/// violations: a card that prints `'* ${check.label}: ${check.guidance}'` is
/// the exact operator-vocabulary dump R12 exists to catch, yet the whole line
/// sits inside quotes and would read as clean. Interpolation contents
/// are therefore preserved as code, and blanked recursively so a string nested
/// inside an interpolation is still treated as text.
String blankNonCode(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final rest = source.length - i;
    final c = source[i];
    final next = rest > 1 ? source[i + 1] : '';

    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      out.write('  ');
      i += 2;
      while (i < source.length &&
          !(source[i] == '*' && _at(source, i + 1) == '/')) {
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < source.length) {
        out.write('  ');
        i += 2;
      }
      continue;
    }

    final raw = c == 'r' && (next == "'" || next == '"');
    final quoteStart = raw ? i + 1 : i;
    final q = _at(source, quoteStart);
    if (q == "'" || q == '"') {
      final triple = source.startsWith(q * 3, quoteStart);
      final delim = triple ? q * 3 : q;
      if (raw) out.write(' ');
      out.write(' ' * delim.length);
      i = quoteStart + delim.length;
      while (i < source.length) {
        if (!raw && source[i] == r'\') {
          out.write('  ');
          i += 2;
          continue;
        }
        if (source.startsWith(delim, i)) {
          out.write(' ' * delim.length);
          i += delim.length;
          break;
        }
        if (!raw && source[i] == r'$' && _at(source, i + 1) == '{') {
          final end = _interpolationEnd(source, i + 1);
          if (end > 0) {
            out.write('  ');
            out.write(blankNonCode(source.substring(i + 2, end)));
            out.write(' ');
            i = end + 1;
            continue;
          }
        }
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}

String _at(String source, int index) =>
    index >= 0 && index < source.length ? source[index] : '';

/// Index of the `}` closing the `${` interpolation whose `{` sits at [open],
/// or -1 when the string ends first.
///
/// Braces nested inside a string literal within the interpolation -- a ternary
/// returning `'{'`, most often a nested `'${...}'` -- must not close it, so
/// quoted spans are skipped whole.
int _interpolationEnd(String source, int open) {
  var depth = 0;
  var i = open;
  while (i < source.length) {
    final c = source[i];
    if (c == "'" || c == '"') {
      final triple = source.startsWith(c * 3, i);
      final delim = triple ? c * 3 : c;
      i += delim.length;
      while (i < source.length) {
        if (source[i] == r'\') {
          i += 2;
          continue;
        }
        if (source.startsWith(delim, i)) {
          i += delim.length;
          break;
        }
        i++;
      }
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

typedef RuleCheck = List<Violation> Function(List<SourceFile> files);

final Map<String, String> ruleTitles = {
  'R1': 'Pages compose, they do not fetch',
  'R2': 'One page, one ViewModel',
  'R3': 'All data access goes through repositories',
  'R4': 'Compose with widgets, not _build methods',
  'R5': 'Widgets are shared, not forked',
  'R6': 'Tokens only \u2014 no raw literals or inline TextStyle',
  'R7': 'Size limits \u2014 files and build()',
  'R8': 'Shared state surfaces that never blank on refresh',
  'R9': 'Interactive elements carry a label or tooltip',
  'R10': 'Shared widgets ship with a golden test',
  'R11': 'Portable widgets belong to the design system',
  'R12': 'Backend check text stays in the technical disclosure',
  'R13': 'Colour comes from the palette, not a constant',
  'R14': "Never read Material's generated colour scheme",
  'R15': 'Design system widgets appear in the gallery',
  'R16': 'The design system depends on Flutter and Lucide only',
  'R19': 'Behaviour is reachable from a test without a widget',
  'R21': 'Errors are mapped, never interpolated',
};

/// Widgets whose whole job is to show a check exactly as the backend wrote it.
///
/// A surface qualifies only if it is collapsed by default and titled so the
/// reader knows they are opting into operator text. Shrink this list; never
/// grow it.
const technicalDisclosureWidgets = <String>{
  '_TechnicalChecks',
  'DataPlaneTechnicalChecks',
};

/// Fields on a readiness check that are authored for an operator.
///
/// `label`, `detail`, and `guidance` are written next to the API call that
/// produced them, in the vocabulary of that check, and read as a database dump
/// when they land in a wizard. Product copy for a check lives
/// in an id-keyed table beside the widget that shows it.
final _backendCheckText = RegExp(
  r'\b\w*(?:[Cc]heck|[Tt]ask|[Bb]locker)\w*[!?]?\.(label|detail|guidance)\b',
);

/// R12 -- a check's own strings render only inside a technical disclosure.
///
/// Without it, a setup wizard can pair a product-copy headline with a bullet
/// list in the audit layer's own vocabulary, in the same card, at the same
/// size.
List<Violation> checkBackendTextStaysTechnical(List<SourceFile> files) {
  final out = <Violation>[];
  for (final file in files.where((f) => f.isScreen || f.isWidget)) {
    for (final match in _backendCheckText.allMatches(file.code)) {
      final owner = _enclosingClass(file, match.start);
      if (technicalDisclosureWidgets.contains(owner)) continue;
      out.add(
        Violation(
          'R12',
          file.path,
          _lineOf(file, match.start),
          'renders check.${match.group(1)} outside a technical disclosure; '
              'add product copy keyed by check id',
        ),
      );
    }
  }
  return out;
}

final _classDeclaration = RegExp(
  r'^\s*(?:final\s+)?class\s+(\w+)',
  multiLine: true,
);

/// Name of the class a source offset sits in, or the empty string at top level.
String _enclosingClass(SourceFile file, int offset) {
  var name = '';
  for (final match in _classDeclaration.allMatches(file.code)) {
    if (match.start > offset) break;
    name = match.group(1)!;
  }
  return name;
}

/// Imports a widget may hold and still be movable into the design system.
///
/// Anything else -- a model, a repository, `AppController`, a service -- ties the
/// widget to this app. Such a widget is not "not portable yet", it is a widget
/// whose signature is wrong: change it to take plain data and callbacks first.
bool _isPortableImport(String uri) =>
    uri.startsWith('dart:') ||
    uri.startsWith('package:flutter/') ||
    uri.startsWith('package:lucide_icons_flutter/') ||
    uri.startsWith('package:ii_os_design_system/') ||
    uri.endsWith('theme/ii_os_theme.dart') ||
    uri.endsWith('theme/ii_os_tokens.dart');

/// Files allowed to reach `ApiClient` directly while the migration lands.
/// Shrink this list; never grow it.
const apiClientAllowlist = <String>{
  'lib/state/app_controller.dart',
  'lib/services/api_client.dart',
};

List<Violation> checkPagesDoNotFetch(List<SourceFile> files) {
  final out = <Violation>[];
  for (final file in files.where((f) => f.isScreen)) {
    _scan(
      file,
      RegExp(r'\.api\.(get|post|patch|put|delete)\b'),
      'R1',
      'screen calls the API directly',
      out,
    );
    _scan(
      file,
      RegExp(r'\bTimer\.periodic\b'),
      'R1',
      'screen owns a poller; move it to the ViewModel',
      out,
    );
    _scan(
      file,
      RegExp(r'\bApiClient\b'),
      'R1',
      'screen references ApiClient',
      out,
    );
  }
  return out;
}

List<Violation> checkApiOnlyInRepositories(List<SourceFile> files) {
  final out = <Violation>[];
  for (final file in files) {
    if (file.isRepository || apiClientAllowlist.contains(file.path)) continue;
    _scan(
      file,
      RegExp(r'\.api\.(get|post|patch|put|delete)\b'),
      'R3',
      'API access outside lib/repositories/',
      out,
    );
  }
  return out;
}

List<Violation> checkNoBuildMethods(List<SourceFile> files) {
  final out = <Violation>[];
  final pattern = RegExp(
    r'^\s*(Widget|List<Widget>|PreferredSizeWidget)\s+_[a-zA-Z0-9_]*\s*\(',
  );
  for (final file in files) {
    if (file.isTheme) continue;
    _scanLines(
      file,
      pattern,
      'R4',
      'private widget-returning method; extract a named StatelessWidget',
      out,
    );
  }
  return out;
}

List<Violation> checkWidgetsAreShareable(List<SourceFile> files) {
  final out = <Violation>[];
  for (final file in files.where((f) => f.isWidget)) {
    if (file.lineCount > 150) {
      out.add(
        Violation(
          'R5',
          file.path,
          1,
          'shared widget file is ${file.lineCount} lines (limit 150)',
        ),
      );
    }
    _scan(
      file,
      RegExp(r'\bAppController\b'),
      'R5',
      'shared widget depends on AppController; take data + callbacks',
      out,
    );
    _scan(
      file,
      RegExp(r'\bBaseViewModel\b'),
      'R5',
      'shared widget depends on a ViewModel; take data + callbacks',
      out,
    );
  }
  return out;
}

final _rawLiteralPatterns = <RegExp, String>{
  RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB)\([^)]*\d'):
      'raw EdgeInsets value',
  RegExp(r'SizedBox\(\s*(height|width):\s*\d'): 'raw SizedBox gap',
  RegExp(r'(BorderRadius|Radius)\.circular\(\s*\d'): 'raw corner radius',
  RegExp(r'(maxWidth|maxHeight|width|height)\s*[<>]=?\s*\d{3}'):
      'raw breakpoint',
  RegExp(r'(?<!const )\bTextStyle\('): 'inline TextStyle',
};

List<Violation> checkTokensOnly(List<SourceFile> files) {
  final out = <Violation>[];
  for (final file in files) {
    if (file.isTheme) continue;
    if (!file.isScreen && !file.isWidget) continue;
    for (final MapEntry(key: pattern, value: label)
        in _rawLiteralPatterns.entries) {
      _scan(file, pattern, 'R6', label, out);
    }
  }
  return out;
}

List<Violation> checkSizeLimits(List<SourceFile> files) {
  final out = <Violation>[];
  for (final file in files) {
    if (file.lineCount > 600) {
      out.add(
        Violation(
          'R7',
          file.path,
          1,
          'file is ${file.lineCount} lines (hard cap 600)',
        ),
      );
    } else if (file.lineCount > 400) {
      out.add(
        Violation(
          'R7',
          file.path,
          1,
          'file is ${file.lineCount} lines (guideline 400)',
        ),
      );
    }
    for (final span in _methodSpans(file)) {
      if (span.length > 80) {
        out.add(
          Violation(
            'R7',
            file.path,
            span.line,
            '${span.name}() is ${span.length} lines (limit 80)',
          ),
        );
      }
    }
  }
  return out;
}

List<Violation> checkRefreshDoesNotBlank(List<SourceFile> files) {
  final out = <Violation>[];
  final guard = RegExp(
    r'if\s*\(\s*!?(_?\w*[Bb]usy|_loading|_?\w*[Ll]oading)\b([^)]*)\)',
  );
  for (final file in files.where((f) => f.isScreen || f.isWidget)) {
    for (final match in guard.allMatches(file.code)) {
      final tail = match.group(2) ?? '';
      if (tail.contains('isEmpty') || tail.contains('== null')) continue;
      final after = file.code.substring(
        match.end,
        (match.end + 200).clamp(0, file.code.length),
      );
      if (!after.contains('CircularProgressIndicator')) continue;
      out.add(
        Violation(
          'R8',
          file.path,
          _lineOf(file, match.start),
          'busy guard replaces content; add "&& items.isEmpty"',
        ),
      );
    }
  }
  return out;
}

List<Violation> checkInteractiveLabels(List<SourceFile> files) {
  final out = <Violation>[];
  final iconButton = RegExp(r'\bIconButton\(');
  for (final file in files.where((f) => f.isScreen || f.isWidget)) {
    for (final match in iconButton.allMatches(file.code)) {
      final window = file.code.substring(
        match.start,
        (match.start + 400).clamp(0, file.code.length),
      );
      if (window.contains('tooltip:') || window.contains('Semantics')) continue;
      out.add(
        Violation(
          'R9',
          file.path,
          _lineOf(file, match.start),
          'IconButton without a tooltip or semantic label',
        ),
      );
    }
  }
  return out;
}

List<Violation> checkGoldenCoverage(
  List<SourceFile> files,
  Set<String> goldenNames,
) {
  final out = <Violation>[];
  for (final file in files.where((f) => f.isWidget)) {
    final stem = file.path.split('/').last.replaceAll('.dart', '');
    // A widget may be covered by several goldens describing its states, e.g.
    // `state_surfaces_busy.png` and `state_surfaces_resolved.png`.
    final covered = goldenNames.any(
      (name) => name == stem || name.startsWith('${stem}_'),
    );
    if (covered) continue;
    out.add(Violation('R10', file.path, 1, 'shared widget has no golden test'));
  }
  return out;
}

/// Widgets in `lib/widgets/` that already depend on nothing but Flutter,
/// Lucide, and the design system.
///
/// These are finished components sitting in the wrong repository. The count is
/// the distance to the target state -- every reusable component owned by
/// `packages/ii_os_design_system` and visible in its gallery -- so it is meant
/// to be driven to zero rather than held flat.
List<Violation> checkPortableWidgets(List<SourceFile> files) {
  final out = <Violation>[];
  // Deliberately reads `raw`: `blankNonCode` empties string literals, which is
  // exactly where an import URI lives. Reading `code` here silently yields no
  // imports, and `every` on an empty list is true, so every widget would look
  // portable.
  final importPattern = RegExp(r"""^\s*import\s+'([^']+)'""", multiLine: true);
  for (final file in files.where((f) => f.isWidget)) {
    final imports = importPattern
        .allMatches(file.raw)
        .map((match) => match.group(1)!)
        .toList();
    if (imports.isNotEmpty && imports.every(_isPortableImport)) {
      out.add(
        Violation(
          'R11',
          file.path,
          1,
          'portable \u2014 move it to packages/ii_os_design_system',
        ),
      );
    }
  }
  return out;
}

final class _MethodSpan {
  const _MethodSpan(this.name, this.line, this.length);

  final String name;
  final int line;
  final int length;
}

final _methodStart = RegExp(
  r'^\s*(?:@override\s*)?(?:Widget|Future<[^>]*>|void|List<Widget>|[A-Z][A-Za-z0-9_<>?, ]*)\s+([_a-zA-Z][a-zA-Z0-9_]*)\s*\(',
);

List<_MethodSpan> _methodSpans(SourceFile file) {
  final spans = <_MethodSpan>[];
  final lines = file.codeLines;
  var start = -1;
  var name = '';
  var depth = 0;
  var opened = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (start < 0) {
      final match = _methodStart.firstMatch(line);
      if (match == null) continue;
      start = i;
      name = match.group(1)!;
      depth = 0;
      opened = false;
    }
    depth += '{'.allMatches(line).length - '}'.allMatches(line).length;
    if (line.contains('{')) opened = true;
    if (line.contains(';') && !opened && depth == 0) {
      start = -1;
      continue;
    }
    if (opened && depth <= 0) {
      spans.add(_MethodSpan(name, start + 1, i - start + 1));
      start = -1;
    }
  }
  return spans;
}

void _scan(
  SourceFile file,
  RegExp pattern,
  String rule,
  String detail,
  List<Violation> out,
) {
  for (final match in pattern.allMatches(file.code)) {
    out.add(Violation(rule, file.path, _lineOf(file, match.start), detail));
  }
}

void _scanLines(
  SourceFile file,
  RegExp pattern,
  String rule,
  String detail,
  List<Violation> out,
) {
  for (var i = 0; i < file.codeLines.length; i++) {
    if (pattern.hasMatch(file.codeLines[i])) {
      out.add(Violation(rule, file.path, i + 1, detail));
    }
  }
}

int _lineOf(SourceFile file, int offset) =>
    '\n'.allMatches(file.code.substring(0, offset)).length + 1;

List<SourceFile> loadSources(Directory root, String relative) {
  final dir = Directory('${root.path}/$relative');
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) {
        final path = file.path.substring(root.path.length + 1);
        return SourceFile(path, file.readAsStringSync());
      })
      .toList(growable: false)
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// R13 -- a colour is read from the palette, never named as a constant.
///
/// `IiOsColors.ink` is a `static const`, so it has one value. Once the product
/// has two modes, naming one in a widget renders a fixed light colour in dark
/// mode -- it looks right in review, it is wrong on screen, and no analyzer
/// error catches it. `IiOsPalette.of(context)` is the only reading that
/// resolves for the mode actually in front of the viewer.
List<Violation> checkColourFromContext(List<SourceFile> files) {
  final out = <Violation>[];
  final pattern = RegExp(r'\bIiOsColors(?:Dark)?\.');
  for (final file in files) {
    if (file.path.startsWith('lib/theme/')) continue;
    _scan(
      file,
      pattern,
      'R13',
      'constant colour renders light in both modes; '
          'read IiOsPalette.of(context)',
      out,
    );
  }
  return out;
}

/// R14 -- Material's generated colour scheme is not the ii-os palette.
///
/// A `ColorScheme` carries roughly thirty roles the palette never defined and
/// `contrast_test` never walks. Reading one puts a colour on screen that nobody
/// chose and nothing verifies.
List<Violation> checkNoMaterialColorScheme(List<SourceFile> files) {
  final out = <Violation>[];
  final pattern = RegExp(r'\bcolorScheme\b');
  for (final file in files) {
    if (file.path.startsWith('lib/theme/')) continue;
    _scan(
      file,
      pattern,
      'R14',
      'colour nobody chose and no contrast test covers; '
          'read IiOsPalette.of(context)',
      out,
    );
  }
  return out;
}

/// Comments blanked, string literals kept -- the mirror image of [blankNonCode].
///
/// A rule that asks "was this written into a sentence a person reads?" needs
/// the sentence to still be there, so [blankNonCode] is the wrong lens for it.
/// `$` is not valid Dart outside a string, so a `$name` surviving here is an
/// interpolation and nothing else. Comments still have to go first, because
/// `$name` is ordinary prose in a doc comment.
///
/// Newlines are preserved so reported line numbers stay true.
String blankComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final next = _at(source, i + 1);

    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      out.write('  ');
      i += 2;
      while (i < source.length &&
          !(source[i] == '*' && _at(source, i + 1) == '/')) {
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < source.length) {
        out.write('  ');
        i += 2;
      }
      continue;
    }

    final raw = c == 'r' && (next == "'" || next == '"');
    final quoteStart = raw ? i + 1 : i;
    final q = _at(source, quoteStart);
    if (q == "'" || q == '"') {
      final triple = source.startsWith(q * 3, quoteStart);
      final delim = triple ? q * 3 : q;
      if (raw) {
        out.write('r');
        i++;
      }
      out.write(delim);
      i += delim.length;
      while (i < source.length) {
        if (!raw && source[i] == r'\' && i + 1 < source.length) {
          out.write(source[i]);
          out.write(source[i + 1]);
          i += 2;
          continue;
        }
        if (source.startsWith(delim, i)) {
          out.write(delim);
          i += delim.length;
          break;
        }
        out.write(source[i]);
        i++;
      }
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}

/// R19 -- behaviour must be reachable from a test without pumping a widget.
///
/// A private extension on a private `State` can only be reached by rendering
/// the whole screen, and the only thing that renders a screen is a golden,
/// which CI does not run. Methods there that merge pull requests, delete
/// tickets, or write status have zero executed assertions while every suite
/// reports green.
///
/// Splitting a long screen across `part` files is fine and encouraged by R7.
/// Hanging behaviour off the `State` it splits is what this catches: move the
/// method to a ViewModel or a repository, where a test can construct it.
List<Violation> checkBehaviourIsTestable(List<SourceFile> files) {
  final out = <Violation>[];
  final pattern = RegExp(r'\bextension\s+_\w+\s+on\s+_\w*State\b');
  for (final file in files) {
    _scan(
      file,
      pattern,
      'R19',
      'behaviour on a private State is unreachable from a test; '
          'move it to a ViewModel or repository',
      out,
    );
  }
  return out;
}

/// Files whose whole job is to carry an exception somewhere it belongs.
///
/// A crash reporter and a bug report exist to transmit the raw text; that is
/// the product, not a leak of it. Shrink this list; never grow it.
const errorTransportFiles = <String>{'lib/services/client_error_reporter.dart'};

/// R21 -- errors are mapped, never interpolated.
///
/// `'$error'` and `error.toString()` are not product copy. A repository maps a
/// failure onto a typed result that names the cause, and the surface renders a
/// sentence written for a person plus a way forward.
/// `'Permission profiles could not be verified: $error'` puts a backend
/// exception on a primary surface, and it renders directly beside a badge
/// claiming the same subject is verified.
///
/// Read from [blankComments] rather than the usual blanked code, because a bare
/// `$error` is blanked as literal text and would otherwise be invisible.
List<Violation> checkErrorsAreMapped(List<SourceFile> files) {
  final out = <Violation>[];
  final pattern = RegExp(r'\$\{?\s*error\b|\berror\.toString\(\)');
  for (final file in files) {
    if (errorTransportFiles.contains(file.path)) continue;
    final text = blankComments(file.raw);
    final lines = text.split('\n');
    for (final match in pattern.allMatches(text)) {
      final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
      // A developer-facing log is not product copy. `debugPrint` is compiled
      // out of a release build and nobody but us ever reads it.
      if (_debugSink.hasMatch(lines[line - 1])) continue;
      out.add(
        Violation(
          'R21',
          file.path,
          line,
          'raw exception text becomes product copy; map the failure to a '
              'typed result and write a sentence for the reader',
        ),
      );
    }
  }
  return out;
}

final RegExp _debugSink = RegExp(r'\b(?:debugPrint|print)\(|\bstderr\.');
