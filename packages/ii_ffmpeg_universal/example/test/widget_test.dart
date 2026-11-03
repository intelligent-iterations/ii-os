import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal_example/main.dart';

void main() {
  testWidgets('example exposes an explicit render action', (tester) async {
    await tester.pumpWidget(const UniversalFfmpegExample());

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Render test clip'), findsOneWidget);
  });
}
