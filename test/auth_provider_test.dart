import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:ii_os/services/google_auth_service.dart';

void main() {
  test('Google sign-in always asks which account to use', () {
    final provider = googleAccountSelectionProvider();

    expect(provider.parameters, {'prompt': 'select_account'});
  });

  test('Android sign-in uses the web OAuth client as its server client', () {
    final ids = nativeGoogleClientIds(
      TargetPlatform.android,
      iosClientId: 'ios-client',
      androidServerClientId: ' android-web-client ',
    );

    expect(ids.clientId, isNull);
    expect(ids.serverClientId, 'android-web-client');
  });

  test('iOS sign-in keeps using the native iOS client', () {
    final ids = nativeGoogleClientIds(
      TargetPlatform.iOS,
      iosClientId: ' ios-client ',
      androidServerClientId: 'android-web-client',
    );

    expect(ids.clientId, 'ios-client');
    expect(ids.serverClientId, isNull);
  });
}
