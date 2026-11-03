import 'package:ii_os_design_system/ii_os_design_system.dart'
    show PromptingGuideSection;

/// Product copy distilled from MiniMax's official H3 video prompting guide.
abstract final class MiniMaxH3PromptingGuide {
  static final sourceUri = Uri.parse(
    'https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/docs/'
    'VIDEO_PROMPT_WRITING_GUIDE_base_en.md',
  );

  static final referenceSourceUri = Uri.parse(
    'https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/docs/'
    'VIDEO_PROMPT_WRITING_GUIDE_ref_en.md',
  );

  static const title = 'Write a stronger MiniMax H3 prompt';

  static const summary =
      'Treat the video as a short audiovisual timeline. Establish the look '
      'and opening composition, then describe what changes moment by moment.';

  static const sections = <PromptingGuideSection>[
    PromptingGuideSection(
      title: 'Build a timed shot sequence',
      body:
          'Start with [Shot 1] and no timestamp. Give later cuts increasing '
          'times that stay inside your chosen duration. Each cut should reveal '
          'a new action, viewpoint, place, state, or moment.',
    ),
    PromptingGuideSection(
      title: 'Direct motion as an action',
      body:
          'Describe the subject\u2019s action and visible result. Write camera '
          'movement naturally\u2014such as a slow, small push-in or a fast, wide '
          'pan\u2014rather than stacking camera keywords.',
    ),
    PromptingGuideSection(
      title: 'Keep people and words consistent',
      body:
          'Keep identity, clothing, props, colours, and spatial relationships '
          'stable. Give each speaking person one speaker ID, identify the '
          'voice once, and preserve the exact dialogue and language.',
    ),
    PromptingGuideSection(
      title: 'Separate scene sound from the score',
      body:
          'Use overall_soundscape for ambience, physical action, and '
          'non-verbal human sounds. Use non_diegetic_music only for music the '
          'audience hears, describing instruments, tempo, rhythm, and dynamics.',
    ),
    PromptingGuideSection(
      title: 'Ask only for what can be seen or heard',
      body:
          'Name the visual style and opening framing. Include synchronized '
          'sound with its action, quote visible on-screen text exactly, and '
          'remove abstract details that have no visual or audible result.',
    ),
  ];

  static const referenceSections = <PromptingGuideSection>[
    PromptingGuideSection(
      title: 'Use the labels shown beside each file',
      body:
          'Picture, Video, and Audio numbering is independent. Define visible '
          'content as stable Subject labels, then cite the exact source label '
          'that supplies identity, style, motion, structure, or sound.',
    ),
    PromptingGuideSection(
      title: 'State the real task relationship',
      body:
          'Begin the summary with reference generation, video editing, video '
          'continuation, audio reuse, or audio reference. Combine only the '
          'relationships the target actually uses.',
    ),
    PromptingGuideSection(
      title: 'Say what stays and what changes',
      body:
          'In retention analysis, mark each referenced subject, picture, '
          'video, or audio as preserved, partially preserved, transferred, '
          'copied, or weakly referenced.',
    ),
    PromptingGuideSection(
      title: 'Direct the result in playback order',
      body:
          'Use detailed_description for the target scene. For an edit, begin '
          'from the source video\u2019s timeline. For a continuation, begin from '
          'its final moment and describe only what happens next.',
    ),
  ];

  static String promptTemplateFor(int durationSeconds) {
    final cutSecond = durationSeconds ~/ 2;
    final cutTimestamp = cutSecond.toString().padLeft(2, '0');
    return '''integrated_multimodal_description: [Shot 1] Cinematic, [framing] establishes [subject and setting]. [Subject action]. The camera [movement]. [Shot 2] At 00:$cutTimestamp.000, the camera cuts to [new information and result].

overall_soundscape: [Ambient sound, action sounds, and non-verbal human sounds.]

non_diegetic_music: [Instrumentation, tempo, rhythm, and dynamics\u2014or N/A.]''';
  }

  static String referencePromptTemplateFor(int durationSeconds) =>
      '''subject_definitions:
<Subject 1> is the desired visible subject from <Picture 1>, preserving [identity details].
<Video 1> is the [source video / motion reference / continuation source].

summary:
[reference generation / video editing / video continuation] [One-sentence target and reference relationship.]

retention_analysis:
<Subject 1>: fully_preserved - [features that stay consistent].
<Video 1>: [fully_preserved / partially_preserved / weak_reference] - [timeline relationship].

detailed_description:
[Shot 1] [Style and opening composition]. [Visible action, camera movement, and synchronized sound]. Keep the full action inside $durationSeconds seconds.

overall_soundscape:
[Ambience, physical action sounds, dialogue, and audio-reference relationship.]

non_diegetic_music:
[Instrumentation, tempo, dynamics, and audio-reference relationship\u2014or N/A.]''';
}
