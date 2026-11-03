Uri buildStorageJsonObjectUri({
  required String bucket,
  required String objectName,
  bool download = false,
  Map<String, String>? queryParameters,
}) => Uri(
  scheme: 'https',
  host: 'storage.googleapis.com',
  pathSegments: [
    if (download) 'download',
    'storage',
    'v1',
    'b',
    bucket,
    'o',
    objectName,
  ],
  queryParameters: queryParameters,
);
