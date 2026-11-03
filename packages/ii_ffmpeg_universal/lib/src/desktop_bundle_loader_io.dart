import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'configuration.dart';

const _maxManifestBytes = 1024 * 1024;
const _maxArtifacts = 512;

Future<FfmpegDesktopBundle> loadAttestedFfmpegDesktopBundle({
  required String rootPath,
  required String manifestSha256,
}) async {
  if (!p.isAbsolute(rootPath) || !_isSha256(manifestSha256)) {
    throw const FormatException('Invalid desktop FFmpeg bundle identity.');
  }
  if (await FileSystemEntity.type(rootPath, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const FormatException(
      'Desktop FFmpeg bundle root is missing, linked, or not a directory.',
    );
  }
  final manifest = File(p.join(rootPath, 'manifest.json'));
  if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Desktop FFmpeg bundle manifest is invalid.');
  }
  final bytes = await manifest
      .openRead(0, _maxManifestBytes + 1)
      .fold<List<int>>(<int>[], (value, chunk) => value..addAll(chunk));
  if (bytes.length > _maxManifestBytes ||
      sha256.convert(bytes).toString() != manifestSha256.toLowerCase()) {
    throw const FormatException(
      'Desktop FFmpeg bundle manifest is unattested.',
    );
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?> ||
      decoded.keys.toSet().difference({
        'schema',
        'platform',
        'architecture',
        'engine_version',
        'closure_sha256',
        'artifacts',
      }).isNotEmpty ||
      decoded.keys.length != 6 ||
      decoded['schema'] != 1 ||
      decoded['platform'] != Platform.operatingSystem ||
      decoded['architecture'] != _currentDesktopArchitecture() ||
      decoded['engine_version'] is! String ||
      !RegExp(
        r'^n[0-9]+\.[0-9]+(?:\.[0-9]+)?$',
      ).hasMatch(decoded['engine_version']! as String) ||
      !_isSha256(decoded['closure_sha256'])) {
    throw const FormatException('Desktop FFmpeg bundle manifest is malformed.');
  }
  final rawArtifacts = decoded['artifacts'];
  if (rawArtifacts is! List ||
      rawArtifacts.length < 2 ||
      rawArtifacts.length > _maxArtifacts) {
    throw const FormatException(
      'Desktop FFmpeg bundle artifact set is invalid.',
    );
  }
  final artifacts =
      <({String name, String role, String sha256, String path})>[];
  final names = <String>{};
  for (final raw in rawArtifacts) {
    if (raw is! Map<String, Object?> ||
        raw.keys.toSet().difference({
          'name',
          'role',
          'architecture',
          'sha256',
        }).isNotEmpty ||
        raw.keys.length != 4) {
      throw const FormatException('Desktop FFmpeg artifact record is invalid.');
    }
    final name = raw['name'];
    final role = raw['role'];
    final digest = raw['sha256'];
    final architecture = raw['architecture'];
    if (name is! String ||
        name.isEmpty ||
        name.length > 128 ||
        p.basename(name) != name ||
        !RegExp(r'^[A-Za-z0-9._+-]+$').hasMatch(name) ||
        role is! String ||
        !{'ffmpeg', 'ffprobe', 'library'}.contains(role) ||
        architecture != decoded['architecture'] ||
        digest is! String ||
        !_isSha256(digest) ||
        !names.add(name.toLowerCase())) {
      throw const FormatException(
        'Desktop FFmpeg artifact identity is invalid.',
      );
    }
    final path = p.join(rootPath, name);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FormatException('Desktop FFmpeg artifact is not regular: $name');
    }
    final actual = await sha256.bind(File(path).openRead()).first;
    if (actual.toString() != digest) {
      throw FormatException('Desktop FFmpeg artifact checksum failed: $name');
    }
    artifacts.add((name: name, role: role, sha256: digest, path: path));
  }
  final ffmpeg = artifacts.where((value) => value.role == 'ffmpeg').toList();
  final ffprobe = artifacts.where((value) => value.role == 'ffprobe').toList();
  if (ffmpeg.length != 1 || ffprobe.length != 1) {
    throw const FormatException('Desktop FFmpeg executables are ambiguous.');
  }
  final canonical =
      artifacts
          .map(
            (value) => {
              'architecture': decoded['architecture']! as String,
              'name': value.name,
              'role': value.role,
              'sha256': value.sha256,
            },
          )
          .toList()
        ..sort((left, right) => left['name']!.compareTo(right['name']!));
  if (sha256.convert(utf8.encode(jsonEncode(canonical))).toString() !=
      decoded['closure_sha256']) {
    throw const FormatException('Desktop FFmpeg closure identity is invalid.');
  }
  return FfmpegDesktopBundle(
    ffmpegPath: ffmpeg.single.path,
    ffmpegSha256: ffmpeg.single.sha256,
    ffprobePath: ffprobe.single.path,
    ffprobeSha256: ffprobe.single.sha256,
    dynamicLibraries: [
      for (final value in artifacts.where((value) => value.role == 'library'))
        FfmpegDesktopDependency(
          name: value.name,
          path: value.path,
          sha256: value.sha256,
        ),
    ],
  );
}

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String _currentDesktopArchitecture() => switch (Abi.current()) {
  Abi.linuxArm64 || Abi.macosArm64 => 'arm64',
  Abi.linuxX64 || Abi.macosX64 => 'x86_64',
  _ => 'unsupported',
};
