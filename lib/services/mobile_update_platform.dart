import 'package:flutter/foundation.dart';

/// Native mobile platforms that can request an ii-os application release.
enum MobileUpdatePlatform {
  android,
  ios;

  String get label => switch (this) {
    MobileUpdatePlatform.android => 'Android',
    MobileUpdatePlatform.ios => 'iOS',
  };

  String workflowKey(String repository) =>
      '$repository#mobile-update-${name.toLowerCase()}';
}

/// Web and desktop builds never expose the mobile release action.
MobileUpdatePlatform? detectMobileUpdatePlatform() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => MobileUpdatePlatform.android,
    TargetPlatform.iOS => MobileUpdatePlatform.ios,
    _ => null,
  };
}
