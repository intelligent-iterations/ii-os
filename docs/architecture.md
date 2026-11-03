# Architecture

ii-os is a self-hostable application with provider boundaries. It is not a
stateless UI kit: Firestore stores tenants and workflow state, while external
providers execute jobs and hold generated assets. Deployment-specific
identities and workflow topology are supplied by the operator.

```text
Flutter clients (web / Android / iOS)
                 |
                 | authenticated JSON API
                 v
+-------------------------------------------------------+
| functions/bin/server.dart                             |
| composition root: validates deployment configuration |
+---------------------------+---------------------------+
                            |
                            v
+-------------------------------------------------------+
| functions/lib/src/api.dart + workflow_api.dart        |
| routes, authorization, orchestration, audit receipts  |
+-----------+----------------------+--------------------+
            |                      |
            v                      v
  domain stores/contracts     provider interfaces
            |                      |
            +----------+-----------+
                       v
        Firebase / GitHub / storage adapters
                       |
                       v
       operator-owned projects and workflow runners
```

The frontend follows the same dependency direction:

```text
lib/main.dart
    -> routing and app controller
        -> feature screens/view models
            -> repositories and API client
                -> HTTP API
```

Reusable client capabilities are ordinary in-repository packages:

```text
packages/
|-- ii_os_design_system/          shared visual primitives and tokens
|-- ii_interactive_sessions/      provider-neutral session contracts
|-- ii_interactive_sessions_flutter/
|-- ii_ui_mcp/                    bounded UI automation protocol
|-- ii_ffmpeg_universal/          backend-neutral media execution
`-- ii_flutter_video_editor/      controlled timeline model and widgets
```

## Where to start

Read these files in order:

1. `lib/main.dart` and `lib/navigation/app_router.dart` for application startup
   and routes.
2. `lib/state/app_controller.dart` for client session and workspace state.
3. `lib/services/api_client.dart` for the client/server boundary.
4. `packages/ii_ffmpeg_universal/lib/ii_ffmpeg_universal.dart` and
   `packages/ii_flutter_video_editor/lib/ii_flutter_video_editor.dart` for the
   media boundary used by the client.
5. `functions/bin/server.dart` for provider composition and configuration.
6. `functions/lib/src/api.dart` and `functions/lib/src/workflow_api.dart` for
   server routing and orchestration.
7. `functions/lib/src/domain.dart` and the provider contracts under
   `functions/lib/src/` before reading concrete adapters under `providers/`.
8. `firestore.rules`, `firestore.indexes.json`, and the matching store tests to
   understand persistence and authorization invariants.

Feature-specific documents in `docs/` explain the larger bounded workflows.
Tests beside each layer are the most precise executable contracts.

## Public source versus implementation

The public source owns reusable application and domain behavior, provider
contracts, generic adapters, platform shells, and tests. An implementation
repository imports an exact public revision and owns account identifiers,
credentials, runner topology, deployment workflows, private runbooks, and
environment-specific mobile signing configuration.

Cross-repository agent trust is disabled by default. A deployment must set an
exact coordinator repository and publication-target allowlist, plus a reviewed
base64 source manifest; missing or invalid configuration fails closed. Mobile
update dispatch likewise requires an explicit implementation repository.
