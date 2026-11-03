/// ii-os's summary of how Qwen Image Edit reads an editing prompt, written in
/// its own words from Qwen's published model material, which is linked at the
/// end of the guide.
const String qwenImageEditModelBible = r'''Qwen Image Edit prompt guide

Model behavior
Qwen Image Edit is the editing variant of the 20B Qwen Image model. It reads the
input image two ways: for meaning (what the people and objects are) and for
appearance (the exact pixels, textures, and lettering). That lets it make two
different kinds of edit, and a good prompt makes clear which one it wants.

Write an instruction, not a description
The image already exists. Say what to change in it as a direct instruction:
"Add ...", "Replace ...", "Remove ...", "Change ... to ...", "Turn the image
into ...". Describe the change and anything that must stay fixed. Do not
describe the whole scene again.

Appearance edits: change one thing, keep the rest
Adding, removing, recoloring, or swapping one element while every other region
stays exactly as it was. Name the target precisely, say where it is, and state
the constraint: "Keep everything else unchanged."
- Add: what to add, where, and how it relates to what is next to it. The model
  usually adds matching shadows and reflections on its own.
- Remove: name the object and where it is.
- Replace or recolor: name the exact element, down to a single garment or a
  single letter, and its new value.
- Background: describe the new setting completely and say that the subject stays
  as it is.
- Clothing and accessories: "Replace the striped shirt with a light grey linen
  jacket." Give placement for accessories: "a navy beret, tilted slightly to the
  left."

Semantic edits: change the picture, keep the identity
Restyling, re-posing, or showing a subject from another angle. Most pixels
change, but the character or object must stay recognizable. Say what changes and
which identity details must hold: face, proportions, colors, outfit, and
distinguishing marks.
- New pose or activity: describe the action and keep the outfit and character
  the same.
- New viewpoint: ask for a specific view (front, left side, right side, back)
  or a rotation in degrees. The model can turn an object fully around.
- Style transfer: name a concrete style, such as watercolor, 3D cartoon, flat
  vector, or chibi, and what must survive the change.

Text in the image
The model can add, delete, and rewrite text in English and Chinese while keeping
the original font, size, and style. Quote the exact current text and the exact
replacement: Change the sign text from "OPEN" to "CLOSED". When the image holds
more than one block of text, say which one, and ask to keep the existing
typography.

Fix hard problems in small steps
For a difficult correction, edit in a chain rather than all at once: one region
or one character per step. When the input image marks a region with a colored
box, refer to it by color and confine the change to it: Replace the text inside
the red box with "2026". Only modify the inside of the box and keep everything
outside it unchanged. If a step only partly succeeds, repeat it on a smaller
region.

Official reference: Qwen, Qwen-Image-Edit-2511 model card,
https://huggingface.co/Qwen/Qwen-Image-Edit-2511''';
