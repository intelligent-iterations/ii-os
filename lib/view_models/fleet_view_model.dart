import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/fleet_repository.dart';

/// Holds the last organization fleet picture loaded by the operator.
final class FleetViewModel extends BaseViewModel {
  FleetViewModel({
    required this.organizationId,
    required this.fleet,
    this.canIssueCredential = false,
  });

  final String organizationId;
  final FleetRepository fleet;

  /// Issuing a reporting credential is org.credentials.manage, which an Admin
  /// does not hold by default. The control is rendered either way, disabled
  /// with the reason beside it rather than enabled and then refused.
  final bool canIssueCredential;

  FleetReport? report;
  String? errorMessage;
  String? selectedMachineId;

  bool _disposed = false;

  bool get hasReport => report != null;

  /// True only before the first successful read, so the skeleton shows once and
  /// a later refresh never blanks the page.
  bool get isFirstLoad => isBusy && report == null;

  FleetMachine? get selectedMachine {
    final id = selectedMachineId;
    if (id == null) return null;
    return report?.machines.where((machine) => machine.id == id).firstOrNull;
  }

  Future<void> start() async {
    await load();
  }

  /// [quiet] refreshes without flickering the page's loading affordances.
  Future<void> load({bool quiet = false}) async {
    if (!quiet) setBusy(true);
    try {
      final next = await fleet.read(organizationId);
      if (_disposed) return;
      report = next;
      errorMessage = null;
    } on Object catch (error) {
      if (_disposed) return;
      // A failed refresh leaves the last good picture on screen; only a failure
      // with nothing to show becomes the error surface.
      errorMessage = error.toString();
    } finally {
      if (!_disposed) {
        if (!quiet) setBusy(false);
        notifyListeners();
      }
    }
  }

  void selectMachine(String? machineId) {
    selectedMachineId = selectedMachineId == machineId ? null : machineId;
    notifyListeners();
  }

  Future<String?> issueCredential(String label) async {
    if (!canIssueCredential) return null;
    return runBusyFuture(
      fleet.issueCredential(organizationId: organizationId, label: label),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
