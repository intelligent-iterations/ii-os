/// Chatterbox Turbo TTS is the one generator in the catalog whose input is not
/// a description of the artifact -- it *is* the artifact. Every other guide here
/// tells the rewriter how to describe something better; this one tells it to
/// leave the words alone and make them speakable.
const String chatterboxNarrationModelBible =
    r'''Chatterbox Turbo TTS narration contract

This field is a script. Every word in it will be spoken aloud to a listener, so
the words themselves are the deliverable. Improve how the script reads to a
voice model without changing what it says.

Preserve exactly:
- The meaning, claims, order of ideas, and tone of the original script.
- The author's vocabulary and sentence voice. Do not upgrade word choice,
  add adjectives, or make the writing more vivid.
- Names, quotations, and any figure the author wrote deliberately.
- Negation. "Do not open the valve" and "Open the valve" are opposite
  instructions; a narration script is never rewritten into affirmative phrasing.
- Length, within a sentence or two. This is a rewrite for speakability, not a
  summary and not an expansion.

Improve for the voice:
- Punctuate for breath. Replace a run-on with two sentences, and use a comma or
  an em dash where a reader would naturally pause. Chatterbox paces from
  punctuation, so punctuation is the pacing control.
- Split any sentence longer than roughly 30 words into clauses that a person
  could say in one breath.
- Write numbers, dates, currency, units, and symbols the way they are spoken:
  "1,200" becomes "twelve hundred", "$4.5M" becomes "four and a half million
  dollars", "10km" becomes "ten kilometres", "%" becomes "percent",
  "Q3 2026" becomes "the third quarter of twenty twenty-six".
- Expand an abbreviation the first time it appears unless it is normally said as
  letters. "e.g." becomes "for example", "approx." becomes "approximately",
  "API" and "CEO" stay as they are.
- Disambiguate a homograph by rephrasing around it when the reading is unclear:
  "read", "lead", "live", "wound", "bass", "close".
- Turn a URL, file path, or code identifier into its spoken form, or drop it
  into a phrase that makes sense heard rather than seen.
- Use a blank line between paragraphs so the model takes a longer beat.

Leave out entirely:
- Stage directions, emotion tags, SSML, bracketed cues, and voice instructions.
  Chatterbox reads what is written, so a bracketed "[warmly]" is spoken as the
  word "warmly".
- Headings, bullet markers, numbering, and any layout that exists for the eye.
  Convert a list into spoken sequence: "First, ... Second, ... Finally, ...".
- Emoji, decorative characters, and repeated punctuation.

Return only the script to be spoken, with no preamble and no commentary.''';
