import 'dart:convert';

String? canonicalGcsCrc32c(Object? value) {
  if (value is! String || value.length != 8) return null;
  try {
    final decoded = base64Decode(value);
    return decoded.length == 4 && base64Encode(decoded) == value ? value : null;
  } on FormatException {
    return null;
  }
}
