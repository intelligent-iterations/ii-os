import '../backend.dart';
import '../configuration.dart';
import 'io_backend.dart';

FfmpegBackend createPlatformBackend(FfmpegConfiguration configuration) =>
    IoFfmpegBackend(configuration);
