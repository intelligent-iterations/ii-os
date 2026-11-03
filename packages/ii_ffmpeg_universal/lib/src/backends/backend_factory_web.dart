import '../backend.dart';
import '../configuration.dart';
import 'web_backend.dart';

FfmpegBackend createPlatformBackend(FfmpegConfiguration configuration) =>
    WebFfmpegBackend(configuration);
