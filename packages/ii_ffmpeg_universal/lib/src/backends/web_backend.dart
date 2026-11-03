@JS()
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../backend.dart';
import '../capabilities.dart';
import '../configuration.dart';
import '../exception.dart';
import '../execution_constraints.dart';
import '../job.dart';
import 'web_asset_location.dart';

@JS('IiFfmpegUniversalBridge')
external _WebBridge? get _globalBridge;

extension type _WebBridge._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> create(
    JSString id,
    JSObject configuration,
    JSFunction onLog,
    JSFunction onProgress,
  );

  external JSPromise<JSAny?> writeFile(
    JSString id,
    JSString name,
    JSUint8Array bytes,
  );

  external JSPromise<_WebExecResult> exec(
    JSString id,
    JSArray<JSString> arguments,
    JSNumber timeoutMilliseconds,
    JSBoolean ffprobe,
  );

  external JSPromise<_WebReadResult> readFileBounded(
    JSString id,
    JSString name,
    JSNumber maxBytes,
    JSBoolean includeBytes,
  );

  external JSPromise<JSAny?> deleteFile(JSString id, JSString name);

  external void terminate(JSString id);
}

extension type _WebExecResult._(JSObject _) implements JSObject {
  external JSNumber get exitCode;
  external JSBoolean get timedOut;
  external JSBoolean get quotaExceeded;
}

extension type _WebReadResult._(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
  external JSNumber get byteLength;
  external JSBoolean get tooLarge;
}

final class WebFfmpegBackend implements FfmpegBackend {
  WebFfmpegBackend(FfmpegConfiguration configuration)
    : _safety = configuration.safety,
      _webBundle = configuration.webBundle,
      _instanceId =
          'ii-ffmpeg-${DateTime.now().microsecondsSinceEpoch}-${_nextInstanceId++}';

  static int _nextInstanceId = 0;
  static const int _maxLogLines = 5000;
  static const int _hardBrowserInputBytes = 128 * 1024 * 1024;
  static const int _hardBrowserOutputBytes = 64 * 1024 * 1024;
  static const int _hardBrowserWorkspaceBytes = 192 * 1024 * 1024;
  static const String _bridgeAsset =
      'assets/packages/ii_ffmpeg_universal/assets/web/'
      'ii_ffmpeg_universal_bridge.js';
  static const String _workerAsset =
      'assets/packages/ii_ffmpeg_universal/assets/web/'
      'ii_ffmpeg_universal_worker.js';

  final FfmpegSafetyPolicy _safety;
  final FfmpegWebBundle? _webBundle;
  final String _instanceId;
  final List<String> _logs = [];
  FfmpegProgressCallback? _progressCallback;
  FfmpegJob? _activeJob;
  FfmpegSafetyPolicy _activeSafety = const FfmpegSafetyPolicy();
  int _logBytes = 0;
  bool _loaded = false;
  bool _cancelRequested = false;
  Future<void>? _initializing;
  Completer<void>? _bridgeLoad;
  web.HTMLScriptElement? _bridgeScript;

  @override
  FfmpegCapabilities get capabilities => FfmpegCapabilities(
    backend: 'ffmpeg.wasm',
    platform: 'web',
    supportsPathInputs: false,
    supportsByteInputs: true,
    supportsFfprobe: true,
    inProcess: true,
    enforcesWorkspaceLimitBeforeWrite: true,
    enforcesEngineMemoryLimit: true,
    acceptsUntrustedMedia: false,
  );

  @override
  Future<void> initialize() {
    if (_loaded) return Future.value();
    final current = _initializing;
    if (current != null) return current;
    final started = _initialize().timeout(
      _safety.defaultTimeout,
      onTimeout: () {
        _cancelBridgeLoad();
        _globalBridge?.terminate(_instanceId.toJS);
        throw const FfmpegException(
          FfmpegErrorCode.engineUnavailable,
          'The browser FFmpeg engine did not initialize before its deadline.',
        );
      },
    );
    _initializing = started;
    return started.whenComplete(() {
      if (identical(_initializing, started)) _initializing = null;
    });
  }

  Future<void> _initialize() async {
    await _loadBridge(_bridgeAsset);
    final bridge = _globalBridge;
    if (bridge == null) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'The packaged ffmpeg.wasm bridge did not initialize.',
      );
    }
    final bundle = _webBundle;
    if (bundle == null) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'Browser execution requires an explicit SHA-256-verified '
        'FfmpegWebBundle.',
      );
    }
    final ffmpegScriptUrl = _verifiedSameOriginUrl(
      bundle.ffmpegScriptUrl,
      bundle.ffmpegScriptSha256,
    );
    final coreScriptUrl = _verifiedSameOriginUrl(
      bundle.coreScriptUrl,
      bundle.coreScriptSha256,
    );
    final coreWasmUrl = _verifiedSameOriginUrl(
      bundle.coreWasmUrl,
      bundle.coreWasmSha256,
    );
    final options =
        <String, Object?>{
              'ffmpegScriptUrl': ffmpegScriptUrl,
              'ffmpegScriptSha256': bundle.ffmpegScriptSha256.toLowerCase(),
              'classWorkerUrl': _resolve(_workerAsset),
              'coreScriptUrl': coreScriptUrl,
              'coreScriptSha256': bundle.coreScriptSha256.toLowerCase(),
              'coreWasmUrl': coreWasmUrl,
              'coreWasmSha256': bundle.coreWasmSha256.toLowerCase(),
              'workspaceLimitBytes': _safety.maxWorkspaceBytes.clamp(
                1,
                _hardBrowserWorkspaceBytes,
              ),
              'readLimitBytes': _hardBrowserOutputBytes,
              'engineMemoryLimitBytes': _safety.maxBrowserEngineMemoryBytes,
            }.jsify()!
            as JSObject;
    final onLog = ((JSString type, JSString message) {
      _recordLog(type.toDart, message.toDart);
    }).toJS;
    final onProgress = ((JSNumber fraction, JSNumber time) {
      final job = _activeJob;
      if (job == null) return;
      final value = fraction.toDartDouble;
      _progressCallback?.call(
        FfmpegProgress(
          jobId: job.id,
          processed: Duration(microseconds: time.toDartInt),
          fraction: value.isFinite ? value.clamp(0.0, 1.0) : null,
        ),
      );
    }).toJS;
    try {
      await bridge.create(_instanceId.toJS, options, onLog, onProgress).toDart;
      _loaded = true;
      if (_cancelRequested) {
        bridge.terminate(_instanceId.toJS);
        _loaded = false;
      }
    } catch (error) {
      throw FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'Unable to load the configured ffmpeg.wasm engine.',
        cause: error,
      );
    }
  }

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) async {
    _activeSafety = safety;
    _cancelRequested = false;
    var totalInputBytes = 0;
    for (final input in job.inputs) {
      if (input is FfmpegPathInput) {
        throw const FfmpegException(
          FfmpegErrorCode.unsupportedPlatform,
          'Browser jobs require byte inputs.',
        );
      }
      if (input is FfmpegBytesInput) totalInputBytes += input.bytes.length;
    }
    if (totalInputBytes > _hardBrowserInputBytes) {
      throw FfmpegException(
        FfmpegErrorCode.inputTooLarge,
        'Browser jobs are capped at $_hardBrowserInputBytes input bytes.',
      );
    }
    for (final output in job.outputs) {
      if (output.destinationPath != null) {
        throw const FfmpegException(
          FfmpegErrorCode.unsupportedPlatform,
          'Browser jobs return bytes; destination paths are unsupported.',
        );
      }
    }
    await initialize();
    if (context.isCancelled || _cancelRequested) {
      return _cancelledResult(job, context);
    }

    final bridge = _globalBridge!;
    _logs.clear();
    _logBytes = 0;
    _activeJob = job;
    _progressCallback = onProgress;
    final started = Stopwatch()..start();
    try {
      for (final input in job.inputs.cast<FfmpegBytesInput>()) {
        // ffmpeg.wasm transfers the supplied ArrayBuffer to its worker. Copy
        // first so a caller's Uint8List is never detached or mutated.
        final transferable = Uint8List.fromList(input.bytes);
        await bridge
            .writeFile(_instanceId.toJS, input.name.toJS, transferable.toJS)
            .toDart;
      }
      if (context.isCancelled) return _cancelledResult(job, context);
      // ffmpeg.wasm prepends `-nostdin -y` inside exec(). Its virtual files are
      // isolated to this instance and removed in the finally block below.
      final arguments = constrainManagedExecution(
        job,
        safety,
        hardOutputBytes: _hardBrowserOutputBytes,
      ).map((argument) => argument.toJS).toList().toJS;
      final execution = await bridge
          .exec(
            _instanceId.toJS,
            arguments,
            context.remaining.inMilliseconds.toJS,
            (job.operation == FfmpegOperation.ffprobe).toJS,
          )
          .toDart;
      final upstreamExitCode = execution.exitCode.toDartInt;
      final timedOut = execution.timedOut.toDart;
      if (execution.quotaExceeded.toDart) {
        throw const FfmpegException(
          FfmpegErrorCode.outputTooLarge,
          'The ffmpeg.wasm workspace reached its hard byte quota.',
        );
      }
      started.stop();
      if (timedOut) _loaded = false;
      final outputs = <String, Uint8List>{};
      var totalOutputBytes = 0;
      if (upstreamExitCode == 0 && !_cancelRequested && !timedOut) {
        for (final output in job.outputs) {
          late Uint8List bytes;
          late int byteLength;
          final limit = executionOutputLimit(
            job,
            output,
            safety,
            hardOutputBytes: _hardBrowserOutputBytes,
          );
          try {
            final read = await bridge
                .readFileBounded(
                  _instanceId.toJS,
                  output.name.toJS,
                  limit.toJS,
                  output.captureBytes.toJS,
                )
                .toDart;
            if (read.tooLarge.toDart) {
              throw FfmpegException(
                FfmpegErrorCode.outputTooLarge,
                '${output.name} is ${read.byteLength.toDartInt} bytes; '
                'the limit is $limit.',
              );
            }
            bytes = output.captureBytes
                ? Uint8List.fromList(read.bytes.toDart)
                : Uint8List(0);
            byteLength = read.byteLength.toDartInt;
          } on FfmpegException {
            rethrow;
          } catch (_) {
            rethrow;
          }
          if (bytes.length > limit) {
            throw FfmpegException(
              FfmpegErrorCode.outputTooLarge,
              '${output.name} exceeds the $limit byte output limit.',
            );
          }
          totalOutputBytes += byteLength;
          if (totalOutputBytes > safety.maxTotalOutputBytes) {
            throw FfmpegException(
              FfmpegErrorCode.outputTooLarge,
              'Declared outputs exceed the '
              '${safety.maxTotalOutputBytes} byte total limit.',
            );
          }
          if (output.captureBytes) outputs[output.name] = bytes;
        }
      }
      return FfmpegResult(
        jobId: job.id,
        backend: capabilities.backend,
        exitCode: upstreamExitCode,
        elapsed: started.elapsed,
        logs: List.unmodifiable(_logs),
        outputBytes: outputs,
        cancelled:
            _cancelRequested || (context.isCancelled && !context.timedOut),
        timedOut: timedOut || context.timedOut,
      );
    } catch (error) {
      if (_cancelRequested) {
        started.stop();
        return FfmpegResult(
          jobId: job.id,
          backend: capabilities.backend,
          exitCode: 255,
          elapsed: started.elapsed,
          logs: List.unmodifiable(_logs),
          outputBytes: const {},
          cancelled: !context.timedOut,
          timedOut: context.timedOut,
        );
      }
      rethrow;
    } finally {
      // Terminating per job is deliberate: it destroys the entire virtual file
      // system, including undeclared side files produced by FFmpeg filters or
      // muxers. Returned bytes have already been copied into Dart-owned memory.
      bridge.terminate(_instanceId.toJS);
      _loaded = false;
      _activeJob = null;
      _progressCallback = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _cancelBridgeLoad();
    _globalBridge?.terminate(_instanceId.toJS);
    _loaded = false;
    final initializing = _initializing;
    if (initializing != null) {
      try {
        await initializing;
      } catch (_) {
        // Initialization owns and reports its own failure.
      }
    }
  }

  @override
  Future<void> dispose() => cancel();

  void _recordLog(String type, String message) {
    if (_logs.length >= _maxLogLines ||
        _logBytes >= _activeSafety.maxLogBytes) {
      return;
    }
    final maxCharacters = _activeSafety.maxLogLineBytes;
    final boundedMessage = message.length <= maxCharacters
        ? message
        : message.substring(0, maxCharacters);
    final encoded = utf8.encode('[$type] $boundedMessage');
    final remaining = _activeSafety.maxLogBytes - _logBytes;
    final acceptedBytes = encoded.length
        .clamp(0, _activeSafety.maxLogLineBytes)
        .clamp(0, remaining);
    if (acceptedBytes == 0) return;
    _logs.add(
      utf8.decode(encoded.sublist(0, acceptedBytes), allowMalformed: true),
    );
    _logBytes += acceptedBytes;
  }

  FfmpegResult _cancelledResult(
    FfmpegJob job,
    FfmpegExecutionContext context,
  ) => FfmpegResult(
    jobId: job.id,
    backend: capabilities.backend,
    exitCode: 255,
    elapsed: context.elapsed,
    logs: List.unmodifiable(_logs),
    outputBytes: const {},
    cancelled: !context.timedOut,
    timedOut: context.timedOut,
  );

  static Uri _resolveLocation(String value) => resolveWebAssetLocation(
    value: value,
    pageLocation: Uri.base,
    documentBaseLocation: web.document.baseURI,
  );

  static String _resolve(String value) => _resolveLocation(value).toString();

  static String _verifiedSameOriginUrl(String value, String sha256) {
    final digest = sha256.toLowerCase();
    final resolved = _resolveLocation(value);
    final origin = Uri.base;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        (resolved.scheme != 'http' && resolved.scheme != 'https') ||
        resolved.scheme != origin.scheme ||
        resolved.host != origin.host ||
        resolved.port != origin.port ||
        resolved.userInfo.isNotEmpty ||
        resolved.fragment.isNotEmpty) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'Browser FFmpeg assets must use same-origin HTTP(S) URLs without '
        'credentials/fragments and exact SHA-256 digests.',
      );
    }
    return resolved.toString();
  }

  Future<void> _loadBridge(String bridgeUrl) {
    if (_globalBridge != null) return Future.value();
    final current = _bridgeLoad;
    if (current != null) return current.future;
    final completer = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = _resolve(bridgeUrl)
      ..async = true;
    _bridgeLoad = completer;
    _bridgeScript = script;
    script.addEventListener(
      'load',
      ((web.Event _) {
        if (!completer.isCompleted) completer.complete();
      }).toJS,
      web.AddEventListenerOptions(once: true),
    );
    script.addEventListener(
      'error',
      ((web.Event _) {
        if (!completer.isCompleted) {
          completer.completeError(
            FfmpegException(
              FfmpegErrorCode.engineUnavailable,
              'Unable to load the packaged browser bridge at ${script.src}.',
            ),
          );
        }
      }).toJS,
      web.AddEventListenerOptions(once: true),
    );
    web.document.head!.appendChild(script);
    return completer.future.whenComplete(() {
      if (identical(_bridgeLoad, completer)) _bridgeLoad = null;
      if (identical(_bridgeScript, script)) _bridgeScript = null;
    });
  }

  void _cancelBridgeLoad() {
    final completer = _bridgeLoad;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        const FfmpegException(
          FfmpegErrorCode.cancelled,
          'Browser bridge loading was cancelled.',
        ),
      );
    }
    _bridgeScript?.remove();
    _bridgeScript = null;
  }
}
