import '../backend.dart';
import '../configuration.dart';
import 'backend_factory_stub.dart'
    if (dart.library.io) 'backend_factory_io.dart'
    if (dart.library.js_interop) 'backend_factory_web.dart'
    as implementation;

FfmpegBackend createPlatformBackend(FfmpegConfiguration configuration) =>
    implementation.createPlatformBackend(configuration);
