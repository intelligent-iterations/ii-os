/// Resolves a browser asset from the document's declared base URL.
///
/// Single-page applications commonly keep [pageLocation] on a deep route while
/// serving all compiled assets from the `<base href>` in the host document.
/// Resolving from the page URL would incorrectly place assets below that route.
Uri resolveWebAssetLocation({
  required String value,
  required Uri pageLocation,
  required String documentBaseLocation,
}) {
  final documentBase = Uri.tryParse(documentBaseLocation);
  final base = documentBase != null && documentBase.hasScheme
      ? documentBase
      : pageLocation;
  return base.resolve(value);
}
