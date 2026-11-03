import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ii_os/navigation/app_route_state.dart';
import 'package:ii_os/navigation/app_router.dart';
import 'package:ii_os/widgets/auth_state_gate.dart';

void main() {
  testWidgets('query navigation keeps the signed-in session subtree alive', (
    tester,
  ) async {
    final authStates = StreamController<_TestUser?>.broadcast();
    var subscriptions = 0;
    final router = createAppRouter(
      initialLocation:
          '/workspaces/workspace-1/storyboards/story-1?panel=panel-1',
      builder: (context, route) => AuthStateGate<_TestUser>(
        createStream: () {
          subscriptions++;
          return authStates.stream;
        },
        waiting: const Text('Starting session'),
        signedOut: const Text('Signed out'),
        signedInBuilder: (context, user) => _SignedInView(route: route),
      ),
    );
    addTearDown(authStates.close);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('Starting session'), findsOneWidget);

    authStates.add(const _TestUser());
    await tester.pump();
    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('Count 1'), findsOneWidget);

    await tester.tap(find.text('Select panel 2'));
    await tester.pumpAndSettle();

    expect(subscriptions, 1);
    expect(find.text('Starting session'), findsNothing);
    expect(find.text('panel-2'), findsOneWidget);
    expect(find.text('Count 1'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/workspaces/workspace-1/storyboards/story-1?panel=panel-2',
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestUser {
  const _TestUser();
}

class _SignedInView extends StatefulWidget {
  const _SignedInView({required this.route});

  final AppRouteState route;

  @override
  State<_SignedInView> createState() => _SignedInViewState();
}

class _SignedInViewState extends State<_SignedInView> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Text(widget.route.query['panel'] ?? 'none'),
          Text('Count $_count'),
          TextButton(
            onPressed: () => setState(() => _count++),
            child: const Text('Increment'),
          ),
          TextButton(
            onPressed: () => context.replace(
              widget.route.withQuery({'panel': 'panel-2'}).location,
            ),
            child: const Text('Select panel 2'),
          ),
        ],
      ),
    );
  }
}
