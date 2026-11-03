/// Inpainting layers on top of a family guide rather than replacing it: the
/// model still reads prompts the way its family does, but the prompt now
/// describes a region of an existing image instead of a whole new one.
const String inpaintingModelBible = r'''Masked-region inpainting contract

The prompt describes what the masked region should contain once it is filled,
not the change being made to it. The model paints the description; it does not
follow an instruction about the previous contents.

Describe the result, never the operation:
- "a plain white cotton t-shirt, its folds and shadows matching the existing
  key light from the upper left" -- not "remove the red shirt".
- "an empty stretch of wet asphalt continuing the road's camber and reflections"
  -- not "delete the car".
- "clear blue sky with thin high cirrus continuing the existing gradient" -- not
  "erase the power lines".

Every inpaint prompt should carry:
1. The subject or surface that now occupies the region, described concretely:
   material, colour, texture, and finish.
2. How it sits in the scene: scale relative to its neighbours, perspective,
   contact points, and occlusion by anything in front of it.
3. Continuity with the untouched image: light direction and softness, colour
   temperature, shadow density, depth of field, grain, and lens character.
4. The seam. State that the filled region blends continuously into the
   surrounding pixels at the mask boundary.

Keep the described content inside the mask. Describing the whole picture invites
the model to restate the rest of the image and drift the parts nobody asked to
change. Describe the region and its immediate contact with what surrounds it.

When the request names something to be gone, translate it into the surface that
would be visible in its place -- the background, the wall, the floor, the sky --
described with the same care as any other subject.''';
