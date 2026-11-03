/// Qwen Image 2512 generates from a description; Qwen-Image-Edit rewrites an
/// image it is given. They are the same family and they read prompts the same
/// way, but a generation prompt written under the editing guide comes out
/// phrased as an instruction to change something that does not exist yet.
const String qwenImageModelBible = r'''Qwen Image 2512 prompt guide

Model behavior
Qwen Image is a 20B instruction-following image model with unusually strong text
rendering in both English and Chinese. It rewards a prompt written as a complete
description of the finished picture, in ordinary prose rather than a keyword
list, and it follows long prompts without losing the early detail.

Structure
Describe the image in the order a viewer takes it in:
1. Medium and framing -- photograph, illustration, 3D render, poster, or diagram,
   with shot scale and camera angle.
2. Subject -- who or what, how many, appearance, wardrobe, expression, and pose.
3. Environment -- setting, background, foreground, and how the subject occupies
   the space.
4. Light -- direction, hardness, colour temperature, and time of day.
5. Colour, mood, and atmosphere.
6. Finish -- lens character, depth of field, texture, material response, and
   rendering style.

Text in the image
This is the model's distinguishing strength, so be exact when the image contains
words. Put the exact string in quotation marks, and say where it sits, what it
is written on, the script or language, the lettering style, its colour, and its
relative size: a shop sign reading "OPEN LATE" in warm neon script across the
window, a poster headline set in heavy condensed sans-serif. Give one or two
text elements the model's full attention rather than a page of copy -- a long
paragraph rendered into an image degrades toward plausible-looking letterforms.

Composition
Use explicit spatial language: centered, rule-of-thirds left, foreground and
background, behind, in front of, to the left of. State the subject count. When
several subjects share the frame, describe them one at a time and say where each
one stands relative to the others.

Consistency across a series
Repeat identity detail verbatim between related images: the same name, the same
face and hair description, the same wardrobe, the same palette. Qwen holds a
character well when the words describing them do not drift.

Affirmative description
Describe the desired state rather than what to leave out. "Single-subject
composition", "crisp focus", "fully clothed", "clean unbranded surfaces", and
"anatomically accurate natural hands" steer the image; an exclusion list mostly
adds the excluded thing's tokens to the prompt.

Return only the prompt.''';
