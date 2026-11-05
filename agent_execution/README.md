# Agent execution

This package is the ii-os side of an agent run. ii-os owns the human workflow:
tenancy, approval, ticket state, admission across runs, recovery and
publication. [II Agent Runtime](https://github.com/intelligent-iterations/ii-agent-runtime)
owns one run: it deploys and removes the isolated worker, enforces its
permissions and limits, and retains the run's configuration and inputs with
their hashes.

The runtime is an ordinary npm dependency pinned to an exact public commit in
`package.json` and `package-lock.json`. `loadInstalledRuntime` refuses to start
when that pin is missing or when a run's recorded runtime revision differs from
the installed one.

## What it does

`executePreparedAgent` imports the installed runtime's configuration and
execution entrypoints. Its caller supplies an explicit target, approval checks,
credential access, artifact collection, retained history and observations. It
fails before acquiring anything when a required integration is absent. Runtime
provisions and tears down the sandbox; ii-os decides workflow and publication
behavior.

`createCodexHarness` keeps native Codex OAuth in a private trusted-controller
home and connects its tool executor through the runtime's bounded stdio
endpoint. The worker receives no OAuth credential. Both sides must run the same
proven Codex version. Local execution, hooks and shell snapshots are disabled,
and Git metadata is denied. Runtime seals external network access; the native
policy permits worker-local sockets needed by Flutter tests and read access to
the worker's `/proc` for Dart executable discovery. Toolchains and caches stay
inside the bounded worker workspace. Codex may refresh its private disposable
auth file; original and refreshed values are redacted before retention, and
the file is removed during cleanup. Ticket runs never receive authority to
replace a stored credential: only the Connect Codex flow does. Raw transcripts
are never retained before credential redaction. Usage reporting runs outside
the worker, including on failure.

Native OAuth model-request and token budgets cannot be enforced by this
adapter, so a configuration that enables those limits fails explicitly. The run
deadline and the target's CPU and memory caps remain required. There is no
API-key fallback.

`openAdmission` keeps a durable reservation ledger for an **explicitly
partitioned allocation**: it must not advertise capacity that another scheduler
also hands out. Reservations survive restart, and every retry of a known
execution returns `recover`, even after release, so the caller reconciles the
original execution and never launches it twice. Only a cleanup receipt that
matches the original identity releases capacity. Admission uses a kernel lock
on a persistent private file; process death releases the lock without changing
any reservation. An unsafe lock file is preserved and the call fails closed.
There is no timeout-based reclamation and no recurring reconciler.

The adapters verify prepared-source integrity, retain immutable inputs,
telemetry and cleanup checkpoints, resolve privately staged GitHub Actions
secrets, invoke the configured usage reporter, and collect a bounded result and
Git bundle through the existing result policy.

`runCodexCredentialVerification` reuses the same Docker binding, harness,
retained inputs and recovery boundary for a fixed credential smoke test. Only
the Connect Codex flow supplies the refreshed-credential hook before its
one-time secret writer.

## Running the tests

```bash
npm ci --ignore-scripts --no-audit --no-fund
npm test
```

Requires Node.js 22.16 or later. `npm ci` builds the pinned runtime from its
public commit; `--ignore-scripts` keeps every other dependency's install
scripts from running. Tests that import the installed runtime establish package
compatibility; mocked targets do not establish deployment or isolation, which
need a live run on a real Docker host.
