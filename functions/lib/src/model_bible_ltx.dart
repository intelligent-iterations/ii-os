/// ii-os's summary of Lightricks' prompting advice for LTX-2.3, written in its
/// own words. The vendor's material is the authority and is linked at the end
/// of the guide.
const String ltxVideoModelBible = r'''LTX-2.3 prompt guide

Model behavior
LTX-2.3 follows long, specific prompts closely. Its text encoder was rebuilt for
this version, so detail about expressions, timing, pauses, and emotional beats
now carries through to the video. Write the prompt the way you would brief a
cinematographer: subject, action, setting, light, camera, and sound.

Length follows duration
Match the amount of description to the length of the clip. A short prompt for a
long clip, such as ten words for eight to ten seconds, leaves the model too
little to fill the time, and it rushes through the action. Longer clips need
longer prompts.

What to include
1. The shot: genre-appropriate cinematography terms and the shot scale.
2. The scene: light, color palette, surface textures, and atmosphere.
3. The action: a natural sequence from beginning to end, in order.
4. The characters: age, hair, clothing, and distinguishing features. Show
   emotion through visible behavior, not labels.
5. The camera: how and when it moves, and what the subject looks like once the
   move ends.
6. The sound: ambience, music, speech, or singing. Put spoken words in
   quotation marks and name the language or accent when it matters.

How to write it
- One flowing paragraph, in the present tense.
- Match detail to shot scale: a close-up needs more than a wide shot.
- Describe camera movement relative to the subject: "the camera circles her",
  "pushes in to his hands".
- Use film language the model understands: tracking shot, slow dolly in, macro
  lens, shallow depth of field, golden hour, low angle, handheld.

Directing dialogue
Split long lines into short phrases and put a physical direction between them:
a pause, a glance away, a breath, a change in voice. This gives the model the
pacing and the acting for each beat, and LTX-2.3 follows that level of
direction.

Sound
For outputs with synchronized audio, describe the acoustic space, the voice
qualities, and the background sounds. Audio detail is worth the words in this
version.

By input type
- Text to video: the model invents everything, so detail is the main lever.
  Cover subject, action, setting, light, camera, and sound.
- Image to video: the first frame already exists. Describe what happens next:
  how the subject moves, how the camera follows, and what can be heard. Do not
  describe what is already visible; describe the move from stillness into
  motion.
- Audio to video: the audio sets the timing. Describe the pictures, subjects,
  and camera work that should accompany it.

Strengths
Cinematic wide, medium, and close shots with considered light and natural
motion; a single subject's expression, small gestures, and facial nuance; fog,
rain, mist, reflections, and golden-hour light; explicit camera instructions;
stylized looks such as painterly, noir, analog film, fashion editorial, or pixel
animation; backlight, rim light, and flickering practical lamps; characters that
speak or sing, in several languages.

Weaknesses to write around
- Emotion labels such as "sad" or "confused": describe what the face and body
  do instead.
- Readable text and logos: not reliable.
- Complex physics and chaotic motion: likely to produce artifacts, although
  dancing usually holds up.
- Crowded scenes: too many characters or actions blur the result.
- Contradictory light: keep one consistent lighting logic.
- Over-engineered prompts: start simple and add layers.

Common mistakes
- Too vague: "a nice nature video" lets the model choose arbitrarily. Say what is
  in the frame.
- Over-specified numbers: exact counts, angles, and speeds work worse than plain
  description.
- Too short for the duration: long clips need long prompts.
- Contradictions: "a perfectly still lake with crashing waves" confuses the
  model. Keep the scene consistent.

Example
A weathered fisherman in a yellow raincoat stands at the bow of a small boat at
dawn, grey swells lifting the hull. Cold blue light breaks through low cloud
behind him. He squints toward the horizon, then raises a hand to shade his eyes.
The camera starts in a medium shot and slowly pushes in to a close-up as spray
beads on his beard. He speaks quietly, "There she is." He pauses, lowers his
hand, and smiles. "Right where she said." Wind gusts, waves slap against the
hull, and a gull calls in the distance.

Useful vocabulary
- Styles: stop-motion, 2D or 3D animation, claymation, hand-drawn, comic book,
  cyberpunk, 8-bit pixel, surreal, minimalist, painterly, period drama, film
  noir, fantasy, space opera, thriller, documentary, arthouse.
- Light: candlelight, neon glow, natural sunlight, hard shadows.
- Texture: rough stone, brushed metal, worn fabric, glossy surfaces.
- Palette: vibrant, muted, monochrome, high contrast.
- Atmosphere: fog, rain, dust, smoke, floating particles.
- Ambience: cafe chatter, wind and rain, forest birdsong.
- Voice: energetic announcer, deep resonant voice, crackling radio, flat robotic
  monotone, curious child; whisper, mutter, shout.
- Camera: follows, tracks, pans across, circles around, tilts up, pushes in,
  pulls back, overhead, handheld, over-the-shoulder, wide establishing shot,
  static frame.
- Film character: grain, lens flare, jittery stop-motion.
- Scale: expansive, epic, intimate, claustrophobic.
- Time: slow motion, time-lapse, rapid cuts, lingering shot, continuous take,
  freeze-frame, fade in or out.
- Effects: particles, motion blur, depth of field.

Official reference: Lightricks, LTX-2, https://github.com/Lightricks/LTX-2''';
