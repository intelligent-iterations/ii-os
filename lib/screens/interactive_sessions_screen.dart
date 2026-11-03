import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import '../repositories/interactive_session_repository.dart';
import '../state/app_controller.dart';
import '../view_models/interactive_sessions_view_model.dart';
import 'interactive_sessions_list.dart';
import 'interactive_terminal_session.dart';

class InteractiveSessionsScreen extends StatelessWidget {
  const InteractiveSessionsScreen({
    required this.controller,
    this.repository,
    this.selectedSessionId,
    this.onSelectSession,
    this.onCloseSession,
    super.key,
  });

  final AppController controller;
  final InteractiveSessionRepository? repository;
  final String? selectedSessionId;
  final ValueChanged<String>? onSelectSession;
  final VoidCallback? onCloseSession;

  @override
  Widget build(BuildContext context) {
    final repository =
        this.repository ?? InteractiveSessionApiRepository(controller.api);
    final selected = selectedSessionId;
    if (selected != null) {
      return InteractiveTerminalSession(
        repository: repository,
        workspaceId: controller.workspace!.id,
        sessionId: selected,
        onClose: onCloseSession,
      );
    }
    return ViewModelBuilder<InteractiveSessionsViewModel>.reactive(
      viewModelBuilder: () => InteractiveSessionsViewModel(
        sessions: repository,
        workspaceId: controller.workspace!.id,
      ),
      onViewModelReady: (model) => model.start(),
      builder: (context, model, _) =>
          InteractiveSessionsList(model: model, onSelect: onSelectSession),
    );
  }
}
