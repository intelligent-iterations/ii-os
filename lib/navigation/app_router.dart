import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_route_state.dart';

typedef AppRouteBuilder =
    Widget Function(BuildContext context, AppRouteState route);

GoRouter createAppRouter({
  required AppRouteBuilder builder,
  String? initialLocation,
  ValueChanged<String>? onNavigation,
}) {
  Page<void> pageFor(BuildContext context, GoRouterState state) {
    onNavigation?.call(
      AppRouteState.fromUri(state.uri).location.split('?').first,
    );
    return NoTransitionPage<void>(
      key: const ValueKey('ii-os-route'),
      child: builder(context, AppRouteState.fromUri(state.uri)),
    );
  }

  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      final route = AppRouteState.fromUri(state.uri);
      final canonical = route.location;
      return canonical == state.uri.toString() ? null : canonical;
    },
    routes: [
      GoRoute(path: '/', pageBuilder: pageFor),
      GoRoute(path: '/github/setup', pageBuilder: pageFor),
      GoRoute(path: '/workspaces/:workspaceId', pageBuilder: pageFor),
      GoRoute(path: '/workspaces/:workspaceId/:page', pageBuilder: pageFor),
      GoRoute(
        path: '/workspaces/:workspaceId/:page/:itemId',
        pageBuilder: pageFor,
      ),
    ],
    errorBuilder: (context, state) => _UnknownRoute(location: state.uri),
  );
}

class _UnknownRoute extends StatelessWidget {
  const _UnknownRoute({required this.location});

  final Uri location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Page not found',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  location.path,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Open ii-os'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
