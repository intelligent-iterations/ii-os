/// Modality fallbacks for a model ii-os has no specific guide for.
///
/// A catalog lives in the customer's repository, so an unknown model is a
/// normal state rather than a bug. What is not acceptable is answering it with
/// a guide from the wrong modality: before this existed, an unrecognised text
/// -to-speech workflow was rewritten under the Z-Image *image* guide, which
/// turned a narration script into a description of a photograph. A generic
/// guide for the right modality is always the better answer, and the resolved
/// bible id says `generic-*` so the metadata shows the guide was not specific.
library;

const String genericImageModelBible = r'''General text-to-image contract

Write one description of the finished image. Order the detail so the most
important decision comes first:

1. Image type and framing: photograph, illustration, render, or diagram; shot
   scale and camera angle.
2. Subject: who or what, how many, their appearance, wardrobe, and pose.
3. Environment: setting, background, foreground, and how the subject sits in it.
4. Light: direction, hardness, colour temperature, and time of day.
5. Colour and mood.
6. Medium and finish: lens character, depth of field, texture, and rendering
   style.

Express every detail as a desired state rather than an exclusion, because most
image models weight the words they are given rather than removing them. Use
"single-subject composition", "crisp focus", "fully clothed", "clean unbranded
surfaces" in place of a negative prompt.

Be concrete where it changes the picture and silent where it does not. Keep
recurring names, faces, wardrobe, and palette identical when the image belongs
to a series.''';

const String genericImageEditModelBible = r'''General image-editing contract

The source image already exists. The prompt describes the image after the edit,
so name what changes and state what must stay identical.

- Say precisely which element changes, and describe its new state concretely.
- Name the parts that must be preserved: the subject's identity and face, the
  framing, the background, the palette, and the lighting, unless the edit is
  meant to change them.
- Match the existing light direction, colour temperature, shadow softness,
  perspective, and grain so the edit belongs to the photograph.
- Make one edit clearly rather than several vaguely. A prompt that changes the
  wardrobe, the background, and the time of day at once usually loses the
  subject's identity along the way.
- Keep any text visible in the image identical unless the edit is the text.''';

const String genericVideoModelBible = r'''General text-to-video contract

Direct a shot, not a still. Cover, in this order:

1. Shot and lens: scale, angle, and lens character.
2. Subject and their appearance, specific enough to stay recognisable
   throughout.
3. The action, as a sequence with a beginning, a middle, and an end that fits
   the requested duration.
4. Camera movement: the path, its speed, and what the frame holds once the move
   completes.
5. Environment, light, weather, and atmosphere.
6. Sound, when the model generates audio: ambience, synchronized effects, and
   whether any voice is intended.

Match the amount of direction to the duration. A short prompt on a long
generation leaves the model to invent the remaining seconds, and it usually
invents a cut. Keep motion physically coherent, name what stays constant across
the shot, and make any transition explicit.''';

const String genericMusicModelBible = r'''General music-generation contract

Write one caption describing the finished piece. Include only attributes that
change what is heard: genre and subgenre, mood, tempo or rhythmic feel,
instrumentation and timbre, vocal character when there are vocals, song
structure, dynamics, arrangement changes, and production or mix qualities.

Prefer observable musical traits over artist names. Keep the caption internally
consistent -- a tempo, a feel, and an instrumentation that belong to the same
piece. Do not write or rewrite lyrics; they travel through their own field.

Return only the caption.''';

const String genericSpeechModelBible = r'''General narration contract

This field is a script and every word in it will be spoken aloud, so preserve
the meaning, the vocabulary, the tone, and the negation exactly as written.
Improve only how it reads to a voice model: punctuate for breath, split any
sentence too long to say in one breath, write numbers, dates, currency, units,
and symbols the way they are spoken, expand abbreviations that are not said as
letters, and remove headings, bullets, emoji, and any layout that exists for the
eye. Leave out stage directions and emotion tags -- they are read aloud as words.

Return only the script to be spoken.''';

const String genericLyricsModelBible = r'''General lyrics contract

These lines are sung as written. Preserve the author's meaning, imagery,
vocabulary, voice, and negation exactly; do not make the writing more poetic.

Mark each section with a tag on its own line -- [Intro], [Verse], [Pre-Chorus],
[Chorus], [Bridge], [Outro] -- keep lines short enough to sing at a natural
breath, keep parallel lines close in syllable count, and repeat a recurring
chorus in full rather than abbreviating it. Keep production notes, chords, and
timestamps out; they are sung aloud if they appear here.

Return only the lyric sheet.''';
