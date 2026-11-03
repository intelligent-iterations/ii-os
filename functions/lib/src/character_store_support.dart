part of 'character_store.dart';

Map<String, Object?> _publicCharacter(String id, Map<String, Object?> data) {
  final answers = _answers(data['answers']);
  final bodyAnswers = _answers(data['bodyAnswers']);
  final clothingAnswers = _answers(data['clothingAnswers']);
  return {
    'id': id,
    'workspaceId': data['workspaceId'],
    'name': data['name'],
    'creationMode': data['creationMode'] == 'image' ? 'image' : 'scratch',
    'sourceAssetId': data['sourceAssetId'],
    'answers': answers,
    'prompt': buildCharacterSheetPrompt(answers),
    'bodyAnswers': bodyAnswers,
    'clothingAnswers': clothingAnswers,
    'bodyPrompt': buildCharacterBodyPrompt(
      answers,
      bodyAnswers,
      clothingAnswers,
    ),
    'status': data['status'],
    'thumbnailUrl': data['thumbnailUrl'],
    'selectedImage': _map(data['selectedImage']),
    'generationJobIds': _generationJobIds(data),
    'lastGenerationJobId': data['lastGenerationJobId'],
    'lastGenerationRequestedAt': _date(data['lastGenerationRequestedAt']),
    'selectedBodyImage': _map(data['selectedBodyImage']),
    'bodyGenerationJobIds': _jobIds(
      data,
      listField: 'bodyGenerationJobIds',
      lastField: 'lastBodyGenerationJobId',
    ),
    'lastBodyGenerationJobId': data['lastBodyGenerationJobId'],
    'lastBodyGenerationRequestedAt': _date(
      data['lastBodyGenerationRequestedAt'],
    ),
    'createdAt': _date(data['createdAt']),
    'updatedAt': _date(data['updatedAt']),
  };
}

List<String> _generationJobIds(Map<String, Object?> data) => _jobIds(
  data,
  listField: 'generationJobIds',
  lastField: 'lastGenerationJobId',
);

List<String> _jobIds(
  Map<String, Object?> data, {
  required String listField,
  required String lastField,
}) {
  final values = data[listField];
  final jobIds = values is List
      ? values.whereType<String>().where((value) => value.isNotEmpty).toList()
      : <String>[];
  final last = data[lastField];
  if (last is String && last.isNotEmpty && !jobIds.contains(last)) {
    jobIds.add(last);
  }
  return jobIds;
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => item.cast<String, Object?>())
      .toList();
}

Map<String, Object?>? _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

Map<String, String> _answers(Object? value) {
  if (value is! Map) return <String, String>{};
  return value.map(
    (key, answer) => MapEntry(key.toString(), answer?.toString() ?? ''),
  );
}

Map<String, String> _validatedAnswers(
  Object? value, {
  required List<String> keys,
  required String errorCode,
}) {
  if (value is! Map) {
    throw ApiError(400, errorCode, 'Character answers must be an object.');
  }
  final raw = value.cast<Object?, Object?>();
  if (raw.keys.any((key) => key is! String || !keys.contains(key))) {
    throw ApiError(
      400,
      errorCode,
      'The questionnaire contains an unknown answer.',
    );
  }
  return {
    for (final key in keys)
      if (raw.containsKey(key)) key: _validatedText(raw[key], key, 1200),
  };
}

String _validatedName(Object? value) {
  final name = _validatedText(value, 'name', 100);
  if (name.isEmpty) {
    throw const ApiError(400, 'invalid_character_name', 'A name is required.');
  }
  return name;
}

String _validatedText(Object? value, String field, int maxLength) {
  if (value is! String || value.length > maxLength) {
    throw ApiError(
      400,
      'invalid_character_$field',
      '$field must be text no longer than $maxLength characters.',
    );
  }
  return value.trim();
}

String _date(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  return '';
}
