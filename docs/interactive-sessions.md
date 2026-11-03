# Interactive terminal sessions

Status: implemented behind explicit server configuration. The browser never
SSHes to a host. The runner control plane places one disposable Docker runtime
in an exact organization pool, and both the runtime supervisor and
participants make outbound WebSocket connections to the session relay.

ii-os expects two external components that are not part of this repository: a
session relay and a runner control plane that accepts job requests, places
leased runtimes on registered hosts, and proves their cleanup. Fleet is
Intelligent Iterations' implementation of that control plane, which is why the
adapter code is named `FleetClient` and `FleetBridge`; any control plane that
implements the same job, lease, and cleanup contract can stand in for it. This
repository provides the API, the control-plane bridge
(`functions/bin/bridge.dart`), the UI, and the session protocol packages that
talk to them.

## Product flow

1. An organization administrator registers an existing runner host and
   assigns it to a pool.
2. The organization grants that exact pool to a workspace with the
   `runtime-docker` and `interactive-pty` capabilities and a concurrency cap.
3. A workspace member opens **Development > Terminal sessions**, explicitly
   refreshes the bounded list, selects an eligible pool, and creates a session.
4. The API registers non-secret session metadata with the relay and atomically
   writes the session, control-plane job request, and concurrency slot. Only
   after that commit succeeds does an authenticated relay callback persist a
   local wake marker and start the bridge.
5. The control plane places the immutable `interactive-session` image only on
   a host in the selected pool. It mints the supervisor grant only for the
   exact assigned host and lease; that grant is not part of the stored
   JobRequest, Firestore record, event stream, environment, or process args.
6. The supervisor consumes the mounted grant, connects outbound to the relay,
   starts a PTY shell, and streams bounded terminal frames. Many participants
   can observe; exactly one input lease holder can write.
7. The owner may invite workspace members as collaborators or viewers, hand
   off input, revoke a participant, or stop the session. Every attach grant is
   session-, role-, generation-, policy-, and expiry-bound and is one-use.
8. The owner may explicitly grant `agent:codex` observe-only or observe-and-act
   access to the current frontend. The frontend publishes a bounded semantic
   snapshot. Screenshots and sensitive actions require a fresh human approval.
9. Stop, expiry, runtime exit, or failure ends the relay session. The control
   plane proves runtime deletion and registrar cleanup before releasing host
   capacity.

No background browser listener, Firestore snapshot listener, or passive
refresh is permitted. Session detail changes arrive over the already-open,
user-started relay WebSocket. The list refreshes only when the user asks.

## Required configuration

The functions server enables this surface only when all four values exist:

- `II_OS_INTERACTIVE_RELAY_URL`: an HTTPS relay origin (loopback HTTP is
  accepted only for tests).
- `II_OS_INTERACTIVE_SESSION_IMAGE`: an immutable OCI image reference ending
  in `@sha256:<64 lowercase hex characters>`.
- `II_OS_INTERACTIVE_GRANT_SIGNING_KEY_SECRET_REF`: a Secret Manager resource
  reference whose UTF-8 payload is base64 for at least 32 random bytes; this
  signs human, frontend, and agent grants.
- `II_OS_INTERACTIVE_RELAY_CONTROL_SECRET_REF`: a Secret Manager resource
  reference whose UTF-8 payload is a 32-8192 character relay control secret.

The secret references are optional string parameters, so a normal functions
deployment does not require or bind interactive-session secrets while the
feature is disabled. When enabled, the function service account must have
access only to those exact Secret Manager versions.

The relay reads those last two values from private files and additionally
requires `II_SESSION_SUPERVISOR_GRANT_KEY_FILE`. The runner control plane
reads the same supervisor key from its own private file. Keep the two signing
keys different: the relay accepts the control-plane key only for a supervisor
claim with exactly `session.join` and `supervisor` capabilities. It accepts installed UI
agent grants only from the user-grant key.

The deployment-owned interactive runtime combines the relay and the bridge.
It binds only to loopback and receives public TLS through the deployment's
approved edge. It keeps at most 8 in-memory sessions, 64 WebSockets, and 4 MiB
of inbound data per connection per second. The bridge receives the control
secret through `II_OS_INTERACTIVE_RELAY_CONTROL_SECRET_FILE`. A terminal
control-plane result ends all remaining relay sockets before the bridge marks
the job unmanaged, so failure and cleanup cannot leave an orphaned live UI or
terminal channel.

## Firestore read-cost budget

Counts below are Firestore document reads. Named databases receive no free
quota; multiply by your database location's current document-read price
([Cloud Firestore pricing](https://cloud.google.com/firestore/pricing)) to
estimate cost. The Admin SDK is used, so Security Rules dependent reads are
zero.

Every access check reads membership, workspace, and organization: 3 reads.
The bounded list returns at most 20 documents. Its equality filter plus one
ordered/range field does not incur index-entry batch reads. Transaction figures
below use one expected attempt and five attempts as the conservative worst
case.

| User operation | Expected reads | Worst-case reads |
| --- | ---: | ---: |
| Create session | 4 | 8 |
| Explicit list refresh (0-20 results) | 4-23 | 23 |
| Get or attach | 4 | 4 |
| Open terminal detail (get + attach) | 8 | 8 |
| Invite human participant | 6 | 10 |
| Invite agent participant | 5 | 9 |
| Issue UI grant | 4 | 4 |
| Revoke participant | 5 | 9 |
| Stop running / queued session | 6 / 7 | 14 / 19 |
| Terminal bridge slot release | 1 | 5 |

The bridge performs no Firestore query on idle startup. An authenticated wake
after the create transaction writes a durable local marker. While that marker
exists, one `bridgeManaged=true` query at five-second cadence returns at most
100 documents; with a pool concurrency cap of one it returns one. Claiming a
queued document adds one exact transaction read, conservatively five under
retry. Terminal jobs set `bridgeManaged=false`, the next bounded
tick clears the marker, and all Firestore reads stop. The worker also stops
after two hours and five minutes and retains the marker for explicit recovery.

An illustrative workload per client per month: 4 sessions, 20 list refreshes
averaging 4 results, 12 terminal-detail opens, 4 human invites, 4 UI
enablements (each one agent invite plus one grant), and 4 stops. Including
bridge reads this is approximately 6,108 reads per client, so 10 clients
read `6,108 × 10 = 61,080` documents per month.

Conservative bounded scenario per client per month: 20 maximum-duration
sessions, 100 full 20-result refreshes, 100 terminal-detail opens, and 20 each
of create, human invite, revoke, UI enablement (agent invite plus grant), stop,
and terminal cleanup at their worst transaction retry counts. This is at most
34,420 reads per client, including the five-minute worker recovery window, so
10 clients read at most `34,420 × 10 = 344,200` documents per month.

Reads scale linearly with clients and with workspaces granted
`interactive-pty`. Increasing the list bound, bridge cadence, session lifetime,
client count, workspace count, or simultaneous `bridgeManaged` records changes
these bounds, so recompute this budget before doing so. Disabling the feature
means removing the four functions settings and the workspace `interactive-pty`
grant; already-started runtime leases then reach their bounded timeout and
cleanup path.

## Security boundaries

- Terminal traffic is relay/WebSocket traffic, not browser SSH.
- Runtime placement is an exact pool identifier, never a mutable capability
  approximation or physical-host selector.
- Jobs have 2 CPU, 2 GiB RAM, 20 GiB disk, and two-hour ceilings.
- Images are immutable digests and runtimes are disposable Docker containers.
- Relay control and grant keys never reach the browser or shell.
- Attach grants are short-lived and one-use. Revocation advances the subject
  generation and closes its live relay connection.
- Terminal input carries the current input-lease revision. Stale writers fail
  closed. Output replay, frames, screenshots, semantic nodes, participants,
  and session lifetime all have protocol limits.
- UI control targets stable semantic IDs and revision numbers; it does not
  synthesize arbitrary coordinates. Screenshot approval and sensitive-action
  approval are separate decisions.
- The runtime owns no runner host credential. It receives only its exact relay
  supervisor grant through an ownership-marked, cleanup-tracked bind mount.
- The terminal shell runs as uid/gid 1000. Its supervisor grant is already
  unlinked, and the UI grant travels by anonymous pipe to a root-owned broker.
  Codex and arbitrary npm children see only the broker's group-scoped Unix
  socket, never either bearer value.
- Leaving or closing the granted frontend clears the relay's semantic snapshot
  and makes observe, screenshot, and action requests fail closed. Flutter also
  rotates the agent generation during teardown so the broker loses authority.

The first relay implementation is intentionally one stateful instance. Session
metadata, consumed attach-token IDs, bounded replay, and live connections are
memory-only. A relay restart therefore fail-closes every socket; the supervisor
exits, the control plane cleans the runtime, and bridge reconciliation
idempotently ends an already-absent relay record. High-availability relay handoff and reconnectable
durable replay are later extensions, not implied by this version.

## Verification

Run `tool/public_quality_gate.sh`; it covers the analyzers, the front-end audit
(see [ii-os-frontend.md](ii-os-frontend.md#running-the-audit)), the package
tests for `ii_interactive_sessions`, `ii_interactive_sessions_flutter`, and
`ii_ui_mcp`, and the functions tests. The external session relay and runner
control plane have their own test suites, which are not part of this
repository.
