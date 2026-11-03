import 'dart:io';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/fleet_bridge.dart';
import 'package:ii_os_functions/src/fleet_client.dart';
import 'package:ii_os_functions/src/providers/relay/http_session_relay_control.dart';
import 'package:ii_os_functions/src/session_relay_control.dart';

Future<void> main(List<String> args) async {
  if (!args.contains('--once')) {
    throw StateError(
      'The standalone bridge permits only --once. Run the push-woken '
      'interactive runtime for durable session reconciliation.',
    );
  }
  final env = Platform.environment;
  final projectId = _required(env, 'II_OS_BRIDGE_PROJECT_ID');
  final databaseId = env['II_OS_FIRESTORE_DATABASE_ID'] ?? 'ii-os';
  final controlPlane = _required(env, 'II_OS_BRIDGE_CONTROL_PLANE_URL');
  final secretFile = File(
    _required(env, 'II_OS_BRIDGE_FLEET_SHARED_SECRET_FILE'),
  );
  final secret = (await secretFile.readAsString()).trim();
  if (secret.isEmpty) throw StateError('Fleet shared-secret file is empty.');
  final workerId = env['II_OS_BRIDGE_WORKER_ID']?.trim().isNotEmpty == true
      ? env['II_OS_BRIDGE_WORKER_ID']!.trim()
      : '${Platform.localHostname}-$pid';
  final relay = await _relayControl(env);
  final bridge = FleetBridge(
    firestore: Firestore(
      settings: Settings(projectId: projectId, databaseId: databaseId),
    ),
    fleet: FleetClient(
      controlPlaneUrl: controlPlane,
      sharedSecret: secret,
      jobTemplatesJson: '',
    ),
    workerId: workerId,
    relay: relay,
  );

  final result = await bridge.tick();
  stdout.writeln('ii-os bridge changed ${result.changed} job(s)');
}

Future<SessionRelayControl?> _relayControl(Map<String, String> env) async {
  final relayUrl = env['II_OS_INTERACTIVE_RELAY_URL']?.trim() ?? '';
  final secretFile =
      env['II_OS_INTERACTIVE_RELAY_CONTROL_SECRET_FILE']?.trim() ?? '';
  if (relayUrl.isEmpty && secretFile.isEmpty) return null;
  if (relayUrl.isEmpty || secretFile.isEmpty) {
    throw StateError(
      'Interactive relay URL and control-secret file must be configured together.',
    );
  }
  final controlSecret = (await File(secretFile).readAsString()).trim();
  return HttpSessionRelayControl(
    baseUri: Uri.parse(relayUrl),
    controlSecret: controlSecret,
  );
}

String _required(Map<String, String> env, String name) {
  final value = env[name]?.trim() ?? '';
  if (value.isEmpty) throw StateError('$name is required.');
  return value;
}
