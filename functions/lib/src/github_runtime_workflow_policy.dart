part of 'github_client.dart';

// The selected workflow declares its execution adapter by step ID. Runtime
// recovery may prove cleanup for finalization, but only the original execution
// output can authorize publication or carry a result to the broker.
bool _runtimeWorkflowSecurityBound(List<Map<String, Object?>> steps) {
  final ids = steps.map((step) => step['id']).whereType<String>().toList();
  if (ids.toSet().length != ids.length) return false;
  Map<String, Object?>? step(String id) =>
      steps.where((value) => value['id'] == id).firstOrNull;
  final execution = step('runtime');
  final observer = step('runtime-cleanup');
  final tokens = step('token-cleanup');
  final authorization = step('publication-authorization');
  final publication = step('publication');
  final finalizer = step('finalization');
  if (execution == null ||
      observer == null ||
      tokens == null ||
      authorization == null ||
      publication == null ||
      finalizer == null) {
    return false;
  }
  final stageIndex = steps.indexWhere((step) => step['id'] == 'token-stage');
  final executionIndex = steps.indexOf(execution);
  final observerIndex = steps.indexOf(observer);
  final tokenIndex = steps.indexOf(tokens);
  final observerEnv = observer['env'];
  final observerTimeout = observer['timeout-minutes'];
  final authorizationEnv = authorization['env'];
  final publicationEnv = publication['env'];
  final finalizerEnv = finalizer['env'];
  const result = r'${{ steps.runtime.outputs.agent_result_b64 }}';
  const bundle = r'${{ steps.runtime.outputs.agent_bundle_artifact_b64 }}';
  const executionReady =
      "steps.runtime.outputs.runtime_cleanup_proven == 'true' && "
      "(steps.runtime.outputs.runtime_usage_proven == 'true' || "
      "steps.runtime.outputs.runtime_execution_never_started == 'true')";
  const observerReady =
      "steps.runtime-cleanup.outputs.runtime_cleanup_proven == 'true' && "
      "(steps.runtime-cleanup.outputs.runtime_usage_proven == 'true' || "
      "steps.runtime-cleanup.outputs.runtime_execution_never_started == 'true')";
  return stageIndex >= 0 &&
      stageIndex < executionIndex &&
      observerIndex > executionIndex &&
      tokenIndex > observerIndex &&
      RegExp(
        r'^\s*python3\s+-m\s+providers\.runtime_ticket\s*$',
        multiLine: true,
      ).hasMatch(execution['run']?.toString() ?? '') &&
      RegExp(
        r'^\s*python3\s+-m\s+providers\.runtime_ticket\s+cleanup\s*$',
        multiLine: true,
      ).hasMatch(observer['run']?.toString() ?? '') &&
      observerTimeout is int &&
      observerTimeout > 0 &&
      observerTimeout <= 20 &&
      observerEnv is Map<String, Object?> &&
      !observerEnv.keys.any(
        (key) => key.contains('PUSH') || key.contains('WRITE'),
      ) &&
      _workflowCondition(observer['if']) ==
          _workflowCondition(
            "always() && !inputs.auth_smoke && "
            "steps.runtime.outputs.runtime_requested == 'true' && "
            "steps.runtime.outputs.runtime_cleanup_proven != 'true'",
          ) &&
      _workflowCondition(tokens['if']) == 'always()' &&
      (tokens['run']?.toString() ?? '').contains("grep -Fxq 'proven=true'") &&
      _workflowCondition(authorization['if']) ==
          _workflowCondition(
            "always() && !inputs.auth_smoke && "
            "steps.token-cleanup.outputs.proven == 'true' && "
            "steps.runtime.outputs.runtime_cleanup_proven == 'true' && "
            "steps.runtime.outputs.runtime_usage_proven == 'true' && "
            "steps.runtime.outputs.agent_bundle_artifact_b64 != ''",
          ) &&
      (authorization['run']?.toString() ?? '').contains(
        '.data.authorized == true',
      ) &&
      authorizationEnv is Map<String, Object?> &&
      authorizationEnv['AGENT_RESULT_B64'] == result &&
      _workflowCondition(publication['if']) ==
          _workflowCondition(
            "steps.publication-authorization.outputs.authorized == 'true'",
          ) &&
      publicationEnv is Map<String, Object?> &&
      publicationEnv['AGENT_RESULT_B64'] == result &&
      publicationEnv['AGENT_BUNDLE_ARTIFACT_B64'] == bundle &&
      finalizerEnv is Map<String, Object?> &&
      finalizerEnv['AGENT_RESULT_B64'] == result &&
      finalizerEnv['AGENT_BUNDLE_ARTIFACT_B64'] == bundle &&
      _workflowCondition(finalizer['if']) ==
          _workflowCondition(
            "always() && !inputs.auth_smoke && "
            "steps.token-cleanup.outputs.proven == 'true' && "
            '(($executionReady) || ($observerReady))',
          );
}

String _workflowCondition(Object? value) {
  if (value is! String) return '';
  var result = value.trim();
  if (result.startsWith(r'${{') && result.endsWith('}}')) {
    result = result.substring(3, result.length - 2).trim();
  }
  final normalized = StringBuffer();
  final whitespace = RegExp(r'\s');
  String? quote;
  var escaped = false;
  for (final rune in result.runes) {
    final character = String.fromCharCode(rune);
    if (quote != null) {
      normalized.write(character);
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == quote) {
        quote = null;
      }
    } else if (character == "'" || character == '"') {
      quote = character;
      normalized.write(character);
    } else if (!whitespace.hasMatch(character)) {
      normalized.write(character);
    }
  }
  return quote == null ? normalized.toString() : '';
}
