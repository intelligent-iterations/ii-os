import 'package:flutter/widgets.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

import 'ui_bridge_controller.dart';

final class InteractiveSemanticElement extends StatefulWidget {
  const InteractiveSemanticElement({
    required this.bridge,
    required this.id,
    required this.role,
    required this.label,
    required this.onAction,
    required this.child,
    this.value = '',
    this.enabled = true,
    this.visible = true,
    this.sensitive = false,
    super.key,
  });

  final InteractiveUiBridgeController bridge;
  final String id;
  final String role;
  final String label;
  final String value;
  final bool enabled;
  final bool visible;
  final bool sensitive;
  final UiElementAction onAction;
  final Widget child;

  @override
  State<InteractiveSemanticElement> createState() =>
      _InteractiveSemanticElementState();
}

final class _InteractiveSemanticElementState
    extends State<InteractiveSemanticElement> {
  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(InteractiveSemanticElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) oldWidget.bridge.unregister(oldWidget.id);
    _register();
  }

  void _register() => widget.bridge.register(
    UiElementBinding(
      node: UiSemanticNode(
        id: widget.id,
        role: widget.role,
        label: widget.label,
        value: widget.value,
        enabled: widget.enabled,
        visible: widget.visible,
        sensitive: widget.sensitive,
      ),
      onAction: widget.onAction,
    ),
  );

  @override
  void dispose() {
    widget.bridge.unregister(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    value: widget.sensitive ? 'Redacted' : widget.value,
    enabled: widget.enabled,
    hidden: !widget.visible,
    button: widget.role == 'button',
    textField: widget.role == 'textbox',
    child: widget.child,
  );
}
