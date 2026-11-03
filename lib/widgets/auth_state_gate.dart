import 'package:flutter/material.dart';

typedef SignedInWidgetBuilder<T extends Object> =
    Widget Function(BuildContext context, T value);

/// Keeps one authentication subscription alive while navigation rebuilds the
/// widgets around it.
class AuthStateGate<T extends Object> extends StatefulWidget {
  const AuthStateGate({
    required this.createStream,
    required this.waiting,
    required this.signedOut,
    required this.signedInBuilder,
    super.key,
  });

  final Stream<T?> Function() createStream;
  final Widget waiting;
  final Widget signedOut;
  final SignedInWidgetBuilder<T> signedInBuilder;

  @override
  State<AuthStateGate<T>> createState() => _AuthStateGateState<T>();
}

class _AuthStateGateState<T extends Object> extends State<AuthStateGate<T>> {
  late final Stream<T?> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.createStream();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T?>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.waiting;
        }
        final value = snapshot.data;
        return value == null
            ? widget.signedOut
            : widget.signedInBuilder(context, value);
      },
    );
  }
}
