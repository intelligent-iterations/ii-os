part of 'operator_shell.dart';

extension _OperatorShellWorkshop on _OperatorShellState {
  void _selectWorkshop(
    String? repository,
    String? projectId,
    WorkshopFilter filter,
    String? ticketId,
  ) {
    _goRoute(
      widget.route.withQuery({
        'repository': repository,
        'project': projectId,
        'filter': filter == WorkshopFilter.active ? null : filter.value,
        'ticket': ticketId,
      }),
    );
  }

  void _selectWorkshopRoom(
    String roomId,
    String? repository,
    String projectId,
  ) {
    _goRoute(
      widget.route.withItem(roomId).withQuery({
        'repository': repository,
        'project': projectId,
        'ticket': null,
      }),
    );
  }
}
