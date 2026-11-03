const String minimaxH3VideoModelBible = r'''MiniMax H3 prompt contract

For text, first-frame, last-frame, and first-plus-last-frame generation, write
one production-ready prompt with exactly these three labeled sections:

1. integrated_multimodal_description: Establish the visual language, then direct a small number of numbered shots. Give later shots exact timestamps such as "[Shot 2] At 00:05.000". Describe subject, action, environment, lighting, materials, camera movement, and continuity in natural cinematic language.
2. overall_soundscape: Direct native stereo ambience and synchronized sound effects. State "No voices or speech" unless dialogue or visible lip sync is intentionally requested.
3. non_diegetic_music: Direct the score and timed musical changes separately from sounds inside the scene.

For a 15-second generation, prefer three deliberate five-second beats over many short unrelated cuts. Keep one recognizable hero subject across shots and state the identity or material details that must remain stable. Use physically coherent motion and make transitions explicit. H3 tends to trade some raw action speed for consistency and stabilization, so prioritize clear staged action over a crowded sequence.

Describe everything the viewer should see and hear. Use shot scale, lens character, camera path, lighting, surface behavior, atmosphere, and temporal cues. Match the amount of prompt detail to the full duration. Keep the final enhanced prompt within 7,000 characters.

For full-reference generation, video editing, and video continuation, instead
write these six official sections in order: subject_definitions, summary,
retention_analysis, detailed_description, overall_soundscape, and
non_diegetic_music. Use <Picture N>, <Video N>, and <Audio N> exactly as listed
in the request's reference map. Define reusable visible content as stable
<Subject N> labels. Begin summary with the accurate relationship, such as
[reference generation], [video editing], or [video continuation]. For editing,
state that the target is an edited version of <Video 1>. For continuation,
state that new action begins from <Video 1>'s final moment. In
retention_analysis, say explicitly what is fully preserved, partially
preserved, transferred, copied, or used only as a reference. Put the main
playback-order direction under detailed_description rather than
integrated_multimodal_description.

Do not ask H3 to render precise titles, captions, logos, watermarks, or other readable text. Put exact typography into deterministic post-production. Avoid contradictory camera or lighting directions, overloaded casts, and more references than the scene needs. When dialogue is requested, quote the exact words, specify the language and voice, and pace short lines with visible acting beats.

The ii-os H3 workflow delivers a user-selected duration from 4 to 15 seconds at
1280x720, 24 fps, H.264 video, and AAC stereo audio. Do not put these encoder
constraints into the creative prose; use the prompt for direction and let the
workflow enforce delivery.''';
