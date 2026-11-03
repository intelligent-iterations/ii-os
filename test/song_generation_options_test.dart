import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/song_generation_options.dart';

void main() {
  test('vocal language choices exactly match the pinned ACE-Step model', () {
    expect(songVocalLanguages.first.code, 'unknown');
    expect(songVocalLanguages.first.label, 'Auto \u2014 match lyrics');
    expect(songVocalLanguages.map((language) => language.code).toSet(), {
      'ar',
      'az',
      'bg',
      'bn',
      'ca',
      'cs',
      'da',
      'de',
      'el',
      'en',
      'es',
      'fa',
      'fi',
      'fr',
      'he',
      'hi',
      'hr',
      'ht',
      'hu',
      'id',
      'is',
      'it',
      'ja',
      'ko',
      'la',
      'lt',
      'ms',
      'ne',
      'nl',
      'no',
      'pa',
      'pl',
      'pt',
      'ro',
      'ru',
      'sa',
      'sk',
      'sr',
      'sv',
      'sw',
      'ta',
      'te',
      'th',
      'tl',
      'tr',
      'uk',
      'ur',
      'vi',
      'yue',
      'zh',
      'unknown',
    });
  });

  test('time signatures use the meter the model actually receives', () {
    expect(songTimeSignatures.map((signature) => signature.label), [
      'Auto',
      '2/4',
      '3/4',
      '4/4',
      '6/8',
    ]);
    expect(songTimeSignatures.last.value, '6');
  });

  test('key choices include accidentals in both supported modes', () {
    expect(songKeyScales, contains('C# minor'));
    expect(songKeyScales, contains('Bb major'));
  });
}
