/// One vocal language accepted by the pinned ACE-Step 1.5 runtime.
final class SongVocalLanguage {
  const SongVocalLanguage(this.code, this.label);

  final String code;
  final String label;
}

/// Auto comes first, followed by common choices and then the remaining model
/// languages alphabetically. Codes deliberately mirror ACE-Step's
/// `VALID_LANGUAGES`; arbitrary locale tags are not accepted by the model.
const songVocalLanguages = <SongVocalLanguage>[
  SongVocalLanguage('unknown', 'Auto \u2014 match lyrics'),
  SongVocalLanguage('en', 'English'),
  SongVocalLanguage('es', 'Spanish'),
  SongVocalLanguage('fr', 'French'),
  SongVocalLanguage('de', 'German'),
  SongVocalLanguage('pt', 'Portuguese'),
  SongVocalLanguage('zh', 'Mandarin Chinese'),
  SongVocalLanguage('yue', 'Cantonese'),
  SongVocalLanguage('ja', 'Japanese'),
  SongVocalLanguage('ko', 'Korean'),
  SongVocalLanguage('hi', 'Hindi'),
  SongVocalLanguage('ar', 'Arabic'),
  SongVocalLanguage('az', 'Azerbaijani'),
  SongVocalLanguage('bg', 'Bulgarian'),
  SongVocalLanguage('bn', 'Bengali'),
  SongVocalLanguage('ca', 'Catalan'),
  SongVocalLanguage('cs', 'Czech'),
  SongVocalLanguage('da', 'Danish'),
  SongVocalLanguage('el', 'Greek'),
  SongVocalLanguage('fa', 'Persian'),
  SongVocalLanguage('fi', 'Finnish'),
  SongVocalLanguage('he', 'Hebrew'),
  SongVocalLanguage('hr', 'Croatian'),
  SongVocalLanguage('ht', 'Haitian Creole'),
  SongVocalLanguage('hu', 'Hungarian'),
  SongVocalLanguage('id', 'Indonesian'),
  SongVocalLanguage('is', 'Icelandic'),
  SongVocalLanguage('it', 'Italian'),
  SongVocalLanguage('la', 'Latin'),
  SongVocalLanguage('lt', 'Lithuanian'),
  SongVocalLanguage('ms', 'Malay'),
  SongVocalLanguage('ne', 'Nepali'),
  SongVocalLanguage('nl', 'Dutch'),
  SongVocalLanguage('no', 'Norwegian'),
  SongVocalLanguage('pa', 'Punjabi'),
  SongVocalLanguage('pl', 'Polish'),
  SongVocalLanguage('ro', 'Romanian'),
  SongVocalLanguage('ru', 'Russian'),
  SongVocalLanguage('sa', 'Sanskrit'),
  SongVocalLanguage('sk', 'Slovak'),
  SongVocalLanguage('sr', 'Serbian'),
  SongVocalLanguage('sv', 'Swedish'),
  SongVocalLanguage('sw', 'Swahili'),
  SongVocalLanguage('ta', 'Tamil'),
  SongVocalLanguage('te', 'Telugu'),
  SongVocalLanguage('th', 'Thai'),
  SongVocalLanguage('tl', 'Filipino'),
  SongVocalLanguage('tr', 'Turkish'),
  SongVocalLanguage('uk', 'Ukrainian'),
  SongVocalLanguage('ur', 'Urdu'),
  SongVocalLanguage('vi', 'Vietnamese'),
];

final _songLanguageCodes = songVocalLanguages
    .map((language) => language.code)
    .toSet();

bool isSupportedSongLanguage(String code) => _songLanguageCodes.contains(code);

final class SongTimeSignature {
  const SongTimeSignature(this.value, this.label);

  final String value;
  final String label;
}

const songTimeSignatures = <SongTimeSignature>[
  SongTimeSignature('', 'Auto'),
  SongTimeSignature('2', '2/4'),
  SongTimeSignature('3', '3/4'),
  SongTimeSignature('4', '4/4'),
  SongTimeSignature('6', '6/8'),
];

/// Familiar enharmonic spellings keep this choice useful without presenting
/// every theoretical spelling in ACE-Step's 70-value validator.
const songKeyScales = <String>[
  '',
  'C major',
  'C# major',
  'D major',
  'Eb major',
  'E major',
  'F major',
  'F# major',
  'G major',
  'Ab major',
  'A major',
  'Bb major',
  'B major',
  'C minor',
  'C# minor',
  'D minor',
  'Eb minor',
  'E minor',
  'F minor',
  'F# minor',
  'G minor',
  'G# minor',
  'A minor',
  'Bb minor',
  'B minor',
];
