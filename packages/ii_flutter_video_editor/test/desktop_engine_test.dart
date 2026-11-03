@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'desktop_engine.dart';

void main() {
  test('Linux dependency discovery uses safe unique base names', () {
    final dependencies = parseElfDependencyPaths('''
linux-vdso.so.1 (0x00007fff00000000)
libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x00007fff00000001)
/lib64/ld-linux-x86-64.so.2 (0x00007fff00000002)
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007fff00000003)
''');

    expect(dependencies, {
      'libz.so.1': '/lib/x86_64-linux-gnu/libz.so.1',
      'ld-linux-x86-64.so.2': '/lib64/ld-linux-x86-64.so.2',
    });
    expect(
      dependencies.keys,
      everyElement(predicate<String>((name) => name == _basename(name))),
    );
  });

  test('Linux dependency discovery rejects one name at two paths', () {
    expect(
      () => parseElfDependencyPaths('''
libexample.so => /opt/first/libexample.so (0x00007fff00000001)
libexample.so => /opt/second/libexample.so (0x00007fff00000002)
'''),
      throwsStateError,
    );
  });
}

String _basename(String path) => path.replaceAll(r'\', '/').split('/').last;
