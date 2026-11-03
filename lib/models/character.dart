import 'models.dart';

final class CharacterModel {
  const CharacterModel({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.creationMode = 'scratch',
    this.sourceAssetId,
    required this.answers,
    required this.prompt,
    this.bodyAnswers = const {},
    this.clothingAnswers = const {},
    this.bodyPrompt = '',
    required this.status,
    required this.thumbnailUrl,
    this.thumbnailImage,
    this.selectedImage,
    this.generationJobIds = const [],
    this.lastGenerationJobId,
    this.lastGenerationRequestedAt,
    this.selectedBodyImage,
    this.bodyGenerationJobIds = const [],
    this.lastBodyGenerationJobId,
    this.lastBodyGenerationRequestedAt,
    this.lastBodyGenerationStatus,
    this.lastBodyGenerationErrorCode,
    this.lastBodyGenerationUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CharacterModel.fromJson(JsonMap json) => CharacterModel(
    id: json['id'] as String? ?? '',
    workspaceId: json['workspaceId'] as String? ?? '',
    name: json['name'] as String? ?? 'Untitled character',
    creationMode: json['creationMode'] as String? ?? 'scratch',
    sourceAssetId: json['sourceAssetId'] as String?,
    answers: _answers(json['answers']),
    prompt: json['prompt'] as String? ?? '',
    bodyAnswers: _answers(json['bodyAnswers']),
    clothingAnswers: _answers(json['clothingAnswers']),
    bodyPrompt: json['bodyPrompt'] as String? ?? '',
    status: json['status'] as String? ?? 'draft',
    thumbnailUrl: json['thumbnailUrl'] as String?,
    thumbnailImage: json['thumbnailImage'] is Map
        ? CharacterImageModel.fromJson(asJsonMap(json['thumbnailImage']))
        : null,
    selectedImage: json['selectedImage'] is Map
        ? CharacterImageReference.fromJson(asJsonMap(json['selectedImage']))
        : null,
    generationJobIds: (json['generationJobIds'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList(),
    lastGenerationJobId: json['lastGenerationJobId'] as String?,
    lastGenerationRequestedAt: DateTime.tryParse(
      json['lastGenerationRequestedAt'] as String? ?? '',
    ),
    selectedBodyImage: json['selectedBodyImage'] is Map
        ? CharacterImageReference.fromJson(asJsonMap(json['selectedBodyImage']))
        : null,
    bodyGenerationJobIds:
        (json['bodyGenerationJobIds'] as List<Object?>? ?? const [])
            .whereType<String>()
            .toList(),
    lastBodyGenerationJobId: json['lastBodyGenerationJobId'] as String?,
    lastBodyGenerationRequestedAt: DateTime.tryParse(
      json['lastBodyGenerationRequestedAt'] as String? ?? '',
    ),
    lastBodyGenerationStatus: json['lastBodyGenerationStatus'] as String?,
    lastBodyGenerationErrorCode: json['lastBodyGenerationErrorCode'] as String?,
    lastBodyGenerationUrl: json['lastBodyGenerationUrl'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );

  final String id;
  final String workspaceId;
  final String name;
  final String creationMode;
  final String? sourceAssetId;
  final Map<String, String> answers;
  final String prompt;
  final Map<String, String> bodyAnswers;
  final Map<String, String> clothingAnswers;
  final String bodyPrompt;
  final String status;
  final String? thumbnailUrl;
  final CharacterImageModel? thumbnailImage;
  final CharacterImageReference? selectedImage;
  final List<String> generationJobIds;
  final String? lastGenerationJobId;
  final DateTime? lastGenerationRequestedAt;
  final CharacterImageReference? selectedBodyImage;
  final List<String> bodyGenerationJobIds;
  final String? lastBodyGenerationJobId;
  final DateTime? lastBodyGenerationRequestedAt;
  final String? lastBodyGenerationStatus;
  final String? lastBodyGenerationErrorCode;
  final String? lastBodyGenerationUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDraft => status == 'draft';
  bool get isScratch => creationMode == 'scratch';
  bool get isImageBased => creationMode == 'image';
  bool get opensScratchBuilder => isScratch && isDraft;
  String? get thumbnailCacheKey => selectedImage?.cacheKey;

  String get presentationStatus {
    if (isDraft) return 'draft';
    if (!isImageBased || selectedImage != null) return 'ready';
    final generationStatus = lastBodyGenerationStatus;
    if (generationStatus == 'failed' || generationStatus == 'cancelled') {
      return generationStatus!;
    }
    if (generationStatus == 'completed') return 'failed';
    if (lastBodyGenerationJobId != null) return 'generating';
    return 'needs generation';
  }

  int get answeredQuestions => characterQuestions
      .where((question) => (answers[question.key] ?? '').trim().isNotEmpty)
      .length;

  int get answeredBodyQuestions => characterBodyQuestions
      .where((question) => (bodyAnswers[question.key] ?? '').trim().isNotEmpty)
      .length;

  int get answeredClothingQuestions => characterClothingQuestions
      .where(
        (question) => (clothingAnswers[question.key] ?? '').trim().isNotEmpty,
      )
      .length;
}

final class CharacterImageReference {
  const CharacterImageReference({
    required this.jobId,
    required this.path,
    required this.generation,
    required this.contentType,
  });

  factory CharacterImageReference.fromJson(JsonMap json) =>
      CharacterImageReference(
        jobId: json['jobId'] as String? ?? '',
        path: json['path'] as String? ?? '',
        generation: json['generation'] as String? ?? '',
        contentType: json['contentType'] as String? ?? '',
      );

  final String jobId;
  final String path;
  final String generation;
  final String contentType;

  String get cacheKey => 'gcs:$generation:$path';
}

final class CharacterImageModel {
  const CharacterImageModel({
    required this.jobId,
    required this.path,
    required this.generation,
    required this.contentType,
    required this.url,
    this.workspaceId = '',
    this.bucket = '',
    this.sizeBytes = 0,
    this.sha256 = '',
    this.readUrl = '',
    this.readUrlExpiresAt,
    this.urlErrorCode,
    this.urlErrorMessage,
    this.isSourceImage = false,
    this.editLabel,
    required this.selected,
    required this.createdAt,
  });

  factory CharacterImageModel.fromJson(JsonMap json) {
    final readGrant = asJsonMap(json['readGrant']);
    final urlError = asJsonMap(json['readGrantError'] ?? json['urlError']);
    final workspaceId = json['workspaceId'] as String? ?? '';
    final jobId = json['jobId'] as String? ?? '';
    final path = json['path'] as String? ?? '';
    final generation = json['generation'] as String? ?? '';
    final contentType = json['contentType'] as String? ?? '';
    final sizeBytes = json['sizeBytes'] as int? ?? 0;
    final sha256 = json['sha256'] as String? ?? '';
    final grantMatches =
        readGrant.isNotEmpty &&
        readGrant['workspaceId'] == workspaceId &&
        readGrant['jobId'] == jobId &&
        readGrant['object'] == path &&
        readGrant['generation'] == generation &&
        readGrant['sizeBytes'] == sizeBytes &&
        readGrant['sha256'] == sha256 &&
        readGrant['contentType'] == contentType;
    return CharacterImageModel(
      jobId: jobId,
      path: path,
      generation: generation,
      contentType: contentType,
      url: json['url'] as String? ?? '',
      workspaceId: workspaceId,
      bucket: grantMatches ? readGrant['bucket'] as String? ?? '' : '',
      sizeBytes: sizeBytes,
      sha256: sha256,
      readUrl: grantMatches ? readGrant['url'] as String? ?? '' : '',
      readUrlExpiresAt: grantMatches
          ? DateTime.tryParse(readGrant['expiresAt'] as String? ?? '')
          : null,
      urlErrorCode: urlError['code'] as String?,
      urlErrorMessage: urlError['message'] as String?,
      isSourceImage: json['sourceImage'] == true,
      editLabel: json['editLabel'] as String?,
      selected: json['selected'] == true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  final String jobId;
  final String path;
  final String generation;
  final String contentType;
  final String url;
  final String workspaceId;
  final String bucket;
  final int sizeBytes;
  final String sha256;
  final String readUrl;
  final DateTime? readUrlExpiresAt;
  final String? urlErrorCode;
  final String? urlErrorMessage;
  final bool isSourceImage;
  final String? editLabel;
  final bool selected;
  final DateTime? createdAt;

  String get filename => path.split('/').last;
  String get cacheKey => 'gcs:$generation:$path';
  bool get hasReadGrant =>
      workspaceId.isNotEmpty &&
      bucket.isNotEmpty &&
      RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) &&
      sizeBytes > 0 &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) &&
      const {'image/jpeg', 'image/png', 'image/webp'}.contains(contentType) &&
      readUrl.isNotEmpty &&
      readUrlExpiresAt != null;

  CharacterImageModel withSelected(bool value) => CharacterImageModel(
    jobId: jobId,
    path: path,
    generation: generation,
    contentType: contentType,
    url: url,
    workspaceId: workspaceId,
    bucket: bucket,
    sizeBytes: sizeBytes,
    sha256: sha256,
    readUrl: readUrl,
    readUrlExpiresAt: readUrlExpiresAt,
    urlErrorCode: urlErrorCode,
    urlErrorMessage: urlErrorMessage,
    isSourceImage: isSourceImage,
    editLabel: editLabel,
    selected: value,
    createdAt: createdAt,
  );
}

final class CharacterQuestion {
  const CharacterQuestion({
    required this.key,
    required this.question,
    required this.example,
    required this.section,
    this.guidance,
  });

  final String key;
  final String question;
  final String example;
  final String section;
  final String? guidance;
}

const characterQuestions = <CharacterQuestion>[
  CharacterQuestion(
    key: 'artStyle',
    question: 'What art style should be used?',
    example: 'Detailed semi-realistic digital character concept art.',
    section: 'Direction',
  ),
  CharacterQuestion(
    key: 'characterIdentity',
    question: 'Who is the character?',
    example: 'A fictional lighthouse keeper in her early forties.',
    section: 'Identity and structure',
  ),
  CharacterQuestion(
    key: 'overallAppearance',
    question: 'What is the character\u2019s overall appearance?',
    example: 'A tall, weathered woman with a calm, observant look.',
    section: 'Identity and structure',
  ),
  CharacterQuestion(
    key: 'skinTone',
    question: 'What is the character\u2019s skin tone and undertone?',
    example: 'Light olive skin with neutral undertones.',
    section: 'Identity and structure',
  ),
  CharacterQuestion(
    key: 'faceShape',
    question: 'What shape is the character\u2019s face?',
    example: 'A long, oval face.',
    section: 'Identity and structure',
  ),
  CharacterQuestion(
    key: 'cheekbonesAndCheeks',
    question: 'What are the character\u2019s cheekbones and cheeks like?',
    example: 'High cheekbones with slightly hollow cheeks.',
    section: 'Identity and structure',
  ),
  CharacterQuestion(
    key: 'jawAndChin',
    question: 'What is the character\u2019s jaw and chin like?',
    example: 'A defined jaw with a small, rounded chin.',
    section: 'Identity and structure',
  ),
  CharacterQuestion(
    key: 'nose',
    question: 'What is the character\u2019s nose like?',
    example: 'A straight, narrow nose with a slight bump on the bridge.',
    section: 'Facial features',
  ),
  CharacterQuestion(
    key: 'eyes',
    question: 'What are the character\u2019s eyes like?',
    example: 'Grey-green, deep-set eyes with fine smile lines at the corners.',
    section: 'Facial features',
  ),
  CharacterQuestion(
    key: 'eyebrows',
    question: 'What are the character\u2019s eyebrows like?',
    example: 'Thin, light-brown eyebrows with a gentle arch.',
    section: 'Facial features',
  ),
  CharacterQuestion(
    key: 'lips',
    question: 'What are the character\u2019s lips like?',
    example: 'Medium lips that rest in a slight, closed smile.',
    section: 'Facial features',
  ),
  CharacterQuestion(
    key: 'ears',
    question: 'What are the character\u2019s ears like?',
    example: 'Average ears, partly covered by hair.',
    section: 'Facial features',
  ),
  CharacterQuestion(
    key: 'hairTypeAndTexture',
    question: 'What is the character\u2019s hair type and texture?',
    example: 'Wavy, medium-thick auburn hair with a few grey strands.',
    section: 'Hair',
  ),
  CharacterQuestion(
    key: 'hairStyle',
    question: 'How is the hair styled?',
    example:
        'Pulled back into a low, loose bun with a few strands framing the face.',
    section: 'Hair',
  ),
  CharacterQuestion(
    key: 'hairline',
    question: 'What is the character\u2019s hairline like?',
    example: 'A softly rounded hairline with a small peak at the centre.',
    section: 'Hair',
  ),
  CharacterQuestion(
    key: 'expression',
    question: 'What expression should remain consistent?',
    example:
        'A neutral, relaxed expression with closed lips and an unfurrowed brow.',
    section: 'Consistency details',
  ),
  CharacterQuestion(
    key: 'physicalQuirks',
    question:
        'What distinctive marks or physical quirks does the character have?',
    example:
        'Subtle facial asymmetry: her anatomical right eyebrow, which appears on the left in the front view, sits slightly higher than her anatomical left eyebrow.',
    section: 'Consistency details',
    guidance:
        'For asymmetry, use anatomical direction and the front-view equivalent (for example: anatomical right = viewer\u2019s left).',
  ),
  CharacterQuestion(
    key: 'identifiableMarks',
    question:
        'Does the character have freckles, scars, moles or other identifiable marks?',
    example: 'A thin pale scar on her chin.',
    section: 'Consistency details',
  ),
  CharacterQuestion(
    key: 'clothing',
    question: 'What is the character wearing?',
    example: 'A navy wool sweater with a rolled collar.',
    section: 'Wardrobe',
  ),
  CharacterQuestion(
    key: 'visibleClothing',
    question: 'What parts of the clothing should be visible?',
    example: 'The collar, upper shoulders and top of the sweater.',
    section: 'Wardrobe',
  ),
  CharacterQuestion(
    key: 'accessories',
    question: 'Are accessories included?',
    example: 'A small brass compass pendant on a leather cord.',
    section: 'Wardrobe',
  ),
  CharacterQuestion(
    key: 'recognizableFeatures',
    question: 'Is there anything else that must remain recognizable?',
    example: 'Her grey-green eyes, chin scar, auburn bun and navy sweater.',
    section: 'Consistency details',
  ),
];

const characterSharedAnswerKeys = <String>{
  'artStyle',
  'characterIdentity',
  'overallAppearance',
};

final characterSharedQuestions = characterQuestions
    .where((question) => characterSharedAnswerKeys.contains(question.key))
    .toList(growable: false);

final characterHeadQuestions = characterQuestions
    .where((question) => !characterSharedAnswerKeys.contains(question.key))
    .toList(growable: false);

const characterBodyQuestions = <CharacterQuestion>[
  CharacterQuestion(
    key: 'heightBuildSilhouetteProportions',
    question:
        'What are the character\u2019s height, overall build, silhouette and proportions?',
    example:
        'Approximately 175 cm tall with a lean, sturdy build and long limbs.',
    section: 'Body',
  ),
  CharacterQuestion(
    key: 'neckShouldersUpperTorso',
    question: 'What are their neck, shoulders and upper torso like?',
    example: 'A long neck, square shoulders and a straight upper torso.',
    section: 'Body',
  ),
  CharacterQuestion(
    key: 'chestWaistAbdomen',
    question: 'What are their chest, waist and abdomen like?',
    example: 'A straight, sturdy torso with a natural waist.',
    section: 'Body',
  ),
  CharacterQuestion(
    key: 'hipsPelvisSeat',
    question: 'What are their hips, pelvis and seat like?',
    example: 'Hips in proportion with the shoulders, without exaggeration.',
    section: 'Body',
  ),
  CharacterQuestion(
    key: 'armsHands',
    question: 'What are their arms and hands like?',
    example: 'Long arms with weathered, capable hands and short nails.',
    section: 'Body',
  ),
  CharacterQuestion(
    key: 'legsFeet',
    question: 'What are their legs and feet like?',
    example: 'Long legs and average-sized feet.',
    section: 'Body',
  ),
  CharacterQuestion(
    key: 'postureAsymmetries',
    question: 'What are their posture and bodily asymmetries like?',
    example:
        'Upright posture; her anatomical right shoulder sits slightly lower than the left.',
    section: 'Body',
  ),
  CharacterQuestion(
    key: 'identifyingBodilyDetails',
    question:
        'Are there any identifying bodily details or especially important proportions?',
    example:
        'A faded anchor tattoo on her left forearm. Preserve her height and long limbs.',
    section: 'Body',
  ),
];

const characterClothingQuestions = <CharacterQuestion>[
  CharacterQuestion(
    key: 'outfitConceptSettingSilhouette',
    question: 'What is the outfit concept, setting and overall silhouette?',
    example: 'Practical coastal workwear with a straight, layered silhouette.',
    section: 'Clothing',
  ),
  CharacterQuestion(
    key: 'completeGarmentsLayering',
    question:
        'What garments make up the complete outfit, and how are they layered?',
    example:
        'A wool sweater over a cotton shirt, an open canvas jacket, straight work trousers, wool socks and lace-up boots.',
    section: 'Clothing',
  ),
  CharacterQuestion(
    key: 'upperGarment',
    question: 'What does the upper garment look like?',
    example:
        'A navy cable-knit wool sweater with a rolled collar and slightly long sleeves.',
    section: 'Clothing',
  ),
  CharacterQuestion(
    key: 'lowerGarment',
    question: 'What does the lower garment look like?',
    example:
        'Straight dark-grey work trousers with reinforced knees and turned-up hems.',
    section: 'Clothing',
  ),
  CharacterQuestion(
    key: 'outerwearDrapedGarment',
    question: 'Is there outerwear or a draped garment, and how is it worn?',
    example:
        'An olive waxed-canvas jacket with patch pockets, worn unbuttoned.',
    section: 'Clothing',
  ),
  CharacterQuestion(
    key: 'materialsColorsDecorativeDetails',
    question:
        'What are the outfit\u2019s materials, colors and decorative details?',
    example:
        'Wool, cotton and waxed canvas in navy, olive, dark grey and brass, with plain stitching and brass buttons.',
    section: 'Clothing',
  ),
  CharacterQuestion(
    key: 'headwearHairstyleInteraction',
    question: 'Is there headwear, and how does it interact with the hairstyle?',
    example:
        'A knitted navy watch cap worn above the bun so the bun stays visible.',
    section: 'Clothing',
  ),
  CharacterQuestion(
    key: 'legwearFootwear',
    question: 'What legwear and footwear are included?',
    example: 'Grey wool socks and brown leather lace-up boots.',
    section: 'Clothing',
  ),
  CharacterQuestion(
    key: 'accessoriesClosuresCarriedObjects',
    question: 'What accessories, closures or carried objects are included?',
    example:
        'A brass compass pendant, a leather belt and a small brass lantern carried in one hand.',
    section: 'Clothing',
  ),
];

Map<String, String> _answers(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, answer) => MapEntry(key.toString(), answer?.toString() ?? ''),
  );
}
