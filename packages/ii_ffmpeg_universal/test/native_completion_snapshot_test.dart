import 'package:ffmpeg_kit_flutter_new_full/abstract_session.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native completion event owns its return-code snapshot', () async {
    final session = AbstractSession.createFFmpegSessionFromMap({
      'sessionId': 41,
      'createTime': 1,
      'startTime': 2,
      'command': '-version',
      'type': 1,
      'returnCode': 0,
    });

    final returnCode = await session.getReturnCode();

    expect(ReturnCode.isSuccess(returnCode), isTrue);
  });
}
