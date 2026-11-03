part of 'io_workspace.dart';

const int _pathChunkBytes = 64 * 1024;

Stream<List<int>> _openPathInput(
  File source,
  FfmpegExecutionContext context,
) async* {
  if (Platform.isWindows) {
    yield* _openPathInputWindows(source, context);
    return;
  }
  if (!Platform.isLinux &&
      !Platform.isAndroid &&
      !Platform.isMacOS &&
      !Platform.isIOS) {
    throw const FfmpegException(
      FfmpegErrorCode.unsupportedPlatform,
      'Path inputs are unsupported on this operating system.',
    );
  }

  final fd = _openRegularFilePosix(source.path);
  if (fd < 0) {
    throw FfmpegException(
      FfmpegErrorCode.invalidJob,
      'Input path could not be opened without following links: '
      '${source.path}',
    );
  }
  final descriptorPath = Platform.isLinux || Platform.isAndroid
      ? '/proc/self/fd/$fd'
      : '/dev/fd/$fd';
  final buffer = calloc<Uint8>(_pathChunkBytes);
  try {
    final type = await FileSystemEntity.type(descriptorPath, followLinks: true);
    if (type != FileSystemEntityType.file) {
      throw FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Input path must identify a regular file: ${source.path}',
      );
    }
    while (true) {
      IoWorkspace._checkCancellation(context);
      final count = _readFilePosix(fd, buffer, _pathChunkBytes);
      if (count < 0) {
        throw FfmpegException(
          FfmpegErrorCode.invalidJob,
          'Input path stopped behaving like a readable regular file: '
          '${source.path}',
        );
      }
      if (count == 0) break;
      yield Uint8List.fromList(buffer.asTypedList(count));
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    calloc.free(buffer);
    _closeFilePosix(fd);
  }
}

Stream<List<int>> _openPathInputWindows(
  File source,
  FfmpegExecutionContext context,
) async* {
  final handle = _openRegularFileWindows(source.path);
  if (_isInvalidWindowsHandle(handle)) {
    throw FfmpegException(
      FfmpegErrorCode.invalidJob,
      'Input path could not be opened without following links: '
      '${source.path}',
    );
  }
  final buffer = calloc<Uint8>(_pathChunkBytes);
  final bytesRead = calloc<Uint32>();
  try {
    if (!_isRegularWindowsHandle(handle)) {
      throw FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Input path must identify a regular non-link file: ${source.path}',
      );
    }
    while (true) {
      IoWorkspace._checkCancellation(context);
      if (!_readFileWindows(handle, buffer, _pathChunkBytes, bytesRead)) {
        throw FfmpegException(
          FfmpegErrorCode.invalidJob,
          'Input path stopped behaving like a readable regular file: '
          '${source.path}',
        );
      }
      final count = bytesRead.value;
      if (count == 0) break;
      yield Uint8List.fromList(buffer.asTypedList(count));
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    calloc.free(bytesRead);
    calloc.free(buffer);
    _closeHandleWindows(handle);
  }
}

typedef _PosixLinkNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _PosixLinkDart = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _ReadNative = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef _ReadDart = int Function(int, Pointer<Uint8>, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

bool _linkFileNoReplacePosix(String source, String target) {
  final link = DynamicLibrary.process()
      .lookupFunction<_PosixLinkNative, _PosixLinkDart>('link');
  final sourcePointer = source.toNativeUtf8();
  final targetPointer = target.toNativeUtf8();
  try {
    return link(sourcePointer, targetPointer) == 0;
  } finally {
    malloc.free(sourcePointer);
    malloc.free(targetPointer);
  }
}

int _openRegularFilePosix(String inputPath) {
  final open = DynamicLibrary.process().lookupFunction<_OpenNative, _OpenDart>(
    'open',
  );
  final inputPointer = inputPath.toNativeUtf8();
  final isApple = Platform.isMacOS || Platform.isIOS;
  final nonBlocking = isApple ? 0x0004 : 0x0800;
  final noFollow = isApple ? 0x0100 : 0x20000;
  final closeOnExec = isApple ? 0x1000000 : 0x80000;
  try {
    return open(inputPointer, nonBlocking | noFollow | closeOnExec);
  } finally {
    malloc.free(inputPointer);
  }
}

int _readFilePosix(int fd, Pointer<Uint8> buffer, int length) =>
    DynamicLibrary.process().lookupFunction<_ReadNative, _ReadDart>('read')(
      fd,
      buffer,
      length,
    );

void _closeFilePosix(int fd) => DynamicLibrary.process()
    .lookupFunction<_CloseNative, _CloseDart>('close')(fd);

final class _ByHandleFileInformation extends Struct {
  @Uint32()
  external int fileAttributes;

  @Array(12)
  external Array<Uint32> remainder;
}

typedef _CreateFileWNative =
    Pointer<Void> Function(
      Pointer<Utf16>,
      Uint32,
      Uint32,
      Pointer<Void>,
      Uint32,
      Uint32,
      Pointer<Void>,
    );
typedef _CreateFileWDart =
    Pointer<Void> Function(
      Pointer<Utf16>,
      int,
      int,
      Pointer<Void>,
      int,
      int,
      Pointer<Void>,
    );
typedef _GetFileInformationNative =
    Int32 Function(Pointer<Void>, Pointer<_ByHandleFileInformation>);
typedef _GetFileInformationDart =
    int Function(Pointer<Void>, Pointer<_ByHandleFileInformation>);
typedef _ReadFileNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Void>,
    );
typedef _ReadFileDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      Pointer<Uint32>,
      Pointer<Void>,
    );
typedef _CloseHandleNative = Int32 Function(Pointer<Void>);
typedef _CloseHandleDart = int Function(Pointer<Void>);

DynamicLibrary get _kernel32 => DynamicLibrary.open('kernel32.dll');

Pointer<Void> _openRegularFileWindows(String inputPath) {
  final createFile = _kernel32
      .lookupFunction<_CreateFileWNative, _CreateFileWDart>('CreateFileW');
  final inputPointer = inputPath.toNativeUtf16();
  try {
    return createFile(
      inputPointer,
      0x80000000,
      0x00000001 | 0x00000002 | 0x00000004,
      nullptr,
      3,
      0x00200000 | 0x08000000,
      nullptr,
    );
  } finally {
    malloc.free(inputPointer);
  }
}

bool _isInvalidWindowsHandle(Pointer<Void> handle) =>
    handle.address == (sizeOf<IntPtr>() == 8 ? 0xffffffffffffffff : 0xffffffff);

bool _isRegularWindowsHandle(Pointer<Void> handle) {
  final information = calloc<_ByHandleFileInformation>();
  try {
    final getInformation = _kernel32
        .lookupFunction<_GetFileInformationNative, _GetFileInformationDart>(
          'GetFileInformationByHandle',
        );
    if (getInformation(handle, information) == 0) return false;
    const directory = 0x00000010;
    const reparsePoint = 0x00000400;
    return information.ref.fileAttributes & (directory | reparsePoint) == 0;
  } finally {
    calloc.free(information);
  }
}

bool _readFileWindows(
  Pointer<Void> handle,
  Pointer<Uint8> buffer,
  int length,
  Pointer<Uint32> bytesRead,
) =>
    _kernel32.lookupFunction<_ReadFileNative, _ReadFileDart>('ReadFile')(
      handle,
      buffer,
      length,
      bytesRead,
      nullptr,
    ) !=
    0;

void _closeHandleWindows(Pointer<Void> handle) =>
    _kernel32.lookupFunction<_CloseHandleNative, _CloseHandleDart>(
      'CloseHandle',
    )(handle);
