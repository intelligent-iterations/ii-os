/// ACE-Step takes the song description and the lyrics through two different
/// inputs, and they want opposite treatment: the description is direction the
/// model may reinterpret, while the lyrics are sung verbatim.
const String aceStepLyricsModelBible = r'''ACE-Step lyrics contract

These lines are sung. They reach the listener as written, so the words are the
deliverable and not a description of one.

Preserve exactly:
- The author's meaning, imagery, story, and point of view.
- Their vocabulary and voice, including deliberate slang, dialect, repetition,
  and imperfect rhyme. Do not make the writing more poetic or more polished.
- Any line the author clearly wrote as a hook or a title line.
- Negation and contradiction. A lyric is free to say "I don't", "never", and
  "no one"; those are words in a song, not prompt exclusions.
- The language the lyrics are written in.

Structure for ACE-Step:
- Mark every section with a tag on its own line: [Intro], [Verse], [Pre-Chorus],
  [Chorus], [Bridge], [Instrumental], [Outro].
- Keep the sections the author implied. If the lyrics arrive unstructured,
  segment them where the meaning turns rather than at a fixed line count.
- Repeat the chorus text in full each time it recurs rather than writing
  "[Chorus] x2" -- ACE-Step sings the characters it is given.
- Keep lines short enough to sing: roughly six to twelve syllables, broken at a
  natural breath. Split a long line rather than compressing it.
- Keep the syllable count of parallel lines close so the melody can repeat.
- Write a sung number as a word, and spell a sung abbreviation out.
- Use a blank line between sections.

Leave out entirely:
- Production notes, instrument directions, tempo, key, and mood. Those belong in
  the song description field and are sung aloud if they appear here.
- Chord symbols, timestamps, bar counts, and performer names.
- Parenthetical stage directions, unless they are backing vocals meant to be
  sung, in which case keep them as sung words.

When the request is instrumental, return an empty result rather than inventing
lyrics.

Return only the lyric sheet, with no preamble and no commentary.''';
