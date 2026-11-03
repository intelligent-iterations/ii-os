/// ii-os's summary of Black Forest Labs' prompting advice for FLUX.2, written
/// in its own words. The vendor's page is the authority and is linked at the
/// end of the guide.
const String fluxImageModelBible = r'''FLUX.2 prompt guide

How FLUX reads a prompt
FLUX.2 accepts very long prompts (up to 32K tokens), but a longer prompt is not
a better one. Treat the prompt as a set of instructions: what kind of image it
is, what it shows, where it happens, and how it should look. Every phrase should
change the picture; cut the ones that do not.

Choosing a length
- Short, roughly 10-30 words: quick concepts, style exploration, fast iteration.
- Medium, roughly 30-80 words: most everyday scenes.
- Long, 80-300 words or more: several subjects, or a tightly directed result.
Start short and add detail only where the result needs it.

A working order
Subject and location first, then style, camera, lighting, color, effect, and
finally supporting elements. Use this as a checklist to draw from, not a form to
fill in: leave out any part that does not improve this particular image.

Lead with the subject
Name the main subject plainly, then what it is doing, how the action feels, and
the mood of the moment. Concrete detail ("a grey heron lifting off a reed bed")
does more than a bare noun ("a bird"). Generic adjectives dilute the prompt.

The building blocks
- Image type: portrait, landscape, top-down view, macro close-up, abstract. It
  sets the composition before anything else is said.
- Subject: who or what, with the details that tell it apart.
- Location: the setting. Changing only the location is a quick way to vary one
  concept.
- Style: the visual language, such as editorial photography, wildlife
  documentary, anime, oil painting, or minimalist product photography. Put it
  early when it matters most.
- Camera: lens, distance, angle, and depth of field. Use it when the
  photographic look matters; skip it when it does not.
- Lighting: soft window light, golden hour, hard direct flash, overcast
  daylight, neon backlight.
- Color: a named palette or a two-color scheme keeps the whole image coherent.
- Effect: film grain, bloom, motion blur, bokeh, double exposure. One or two at
  most; more makes the image feel unfocused.
- Supporting elements: dust in the air, falling leaves, reflections on wet
  pavement, objects scattered on a table.

Art form and medium
Naming both the art form and the style gives the most specific look.
- Photography for realism: control framing, light, lens, and depth of field.
- Painting for texture and interpretation: a technique such as oil or
  watercolor, a movement such as impressionism.
- Illustration for a drawn result: pencil, charcoal, cartoon, poster.
- Digital art for a synthetic or graphic look.
- A film still for a cinematic, emotionally charged frame.
Sculpture, collage, street art, textile, ceramic, and print processes also work.
Keep any combination of forms coherent.

Framing and word order
Word order affects framing. When the model pulls back further than wanted, state
the subject and its expression first and move the surroundings later: "a climber
with a focused expression, storm clouds behind her, close-up" frames tighter
than a prompt that opens with the storm. Useful framing terms: close-up, medium
shot, wide shot, overhead view, point-of-view shot, dutch angle, low angle.

Detail and realism
One or two cues such as "highly detailed" or "sharp texture detail" help. A pile
of generic quality words does not.

Building a prompt up
1. Type and subject: portrait, an elderly fisherman mending a net
2. Add the place: ..., on a weathered wooden pier
3. Add direction: ..., documentary photography, 50mm lens, soft overcast light
4. Refine: ..., muted blue and rust palette, fine film grain, gulls blurred in
   the background

Practical rules
- Open with the image type and the subject.
- If the result looks generic, add style and lighting next.
- Use color when the image needs to hang together.
- Add effects and supporting elements last; they refine, they do not carry.
- Remove any phrase that does not visibly change the result.

Official reference: Black Forest Labs, "Building a Good Prompt",
https://docs.bfl.ml/guides/prompting_unified_building''';
