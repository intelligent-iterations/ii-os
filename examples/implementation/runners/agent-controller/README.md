# Agent controller host

Every agent job (work tickets, Connect Codex, credential verification and the
permission installer) runs on the runner named by `II_OS_AGENT_RUNS_ON`. That
runner is the **explicitly bound runtime host**: the trusted controller runs as
the job's own process there, and the agent runtime starts each agent in an
isolated worker container on the same machine. Nothing infers the location
from where a workflow happens to run; the job stops unless the host declares
the identity in `II_OS_AGENT_HOST_ID`.

## Why the controller needs the host's Docker

The agent runtime provisions the worker with OpenTofu against the host's
Docker Engine (`unix:///var/run/docker.sock`), loads a user-namespace AppArmor
profile, and seals each worker's network with `iptables`/`ip6tables` rules on
that worker's private bridge. Those are root-equivalent operations on the
host. The runtime is designed to perform them from **the destination's
ephemeral runner**, so the safe arrangement is:

- **Dedicate the host.** It runs agent jobs and nothing else, and one job at a
  time (register exactly one runner on it, with a label no other workflow uses).
- **Prefer a single-use host.** A fresh VM (or microVM) per job, destroyed
  afterwards, makes the controller's host access worthless to anything that
  survives the job. Container-based runner platforms qualify only if each job
  gets its own Docker Engine and network namespace that are destroyed with it.
- **Run the controller as the job process.** Do not run it in a long-lived
  container that mounts the host's Docker socket with `--network host` and
  `NET_ADMIN` on a shared, persistent machine: whoever compromises that
  container owns the host and every other workload on it.
- The untrusted agent never receives Docker access, credentials or the host
  network; the runtime seals its network after dependency setup and keeps
  credentials in the controller.

## Host contract

The preflight step (`python3 -m providers.runtime_ticket preflight`) checks each
item and stops with a named error when one is missing.

| Requirement | Why |
| --- | --- |
| Linux amd64 with Docker Engine; the runner user can use it | runtime provisions workers |
| Passwordless `sudo` for `iptables` and `ip6tables` for the runner user | runtime seals worker networks |
| AppArmor enabled in the kernel | user-namespace policy for the worker |
| `/usr/local/bin/node` 22.16+, `/usr/local/bin/codex` at the pinned version, `docker`, `tofu`, `gh`, `/usr/bin/python3` 3.10+, `git`, `jq`, `curl`, `bash` | controller toolchain at the paths the reviewed execution binding names |
| `/opt/ii-os/agent_execution` (installed) and `/opt/ii-os/agent-controller.json` | ii-os's execution package at the pinned commit |
| `/etc/ii-os/agent-host-id` equal to `II_OS_AGENT_HOST_ID` | explicit runtime target binding |
| `/workspace`, owned by the runner user, empty | native Codex's controller-side placeholder |
| `II_OS_AGENT_STATE_DIR`: absolute, canonical, owned by the runner user, mode 0700, persistent | admission ledger, execution history, retained results |

`Dockerfile` here builds that toolchain from the same public base-image digests
the agent runtime's own live proof uses. Use it as the base of your single-use
runner image (add your runner agent, a runner user in the `docker` group, a
sudoers rule for `iptables`/`ip6tables`, and `/workspace` owned by that user),
or reproduce its steps in a VM image.

## State and recovery

`II_OS_AGENT_STATE_DIR` holds ii-os's admission ledger for the operator's
**explicitly partitioned** allocation (`II_OS_AGENT_ALLOCATION`) and each
execution's retained inputs, history and cleanup receipts. A rerun of a failed
workflow recovers the original execution from this directory; it never
launches the agent again, and capacity is released only by a cleanup receipt.

On single-use hosts, mount persistent storage at this path (one volume per
allocation, with working POSIX advisory locks) if you want reruns to recover.
Without it a lost host cannot prove cleanup, so ii-os keeps the ticket claimed
and an owner resets it. Never let two schedulers hand out the same capacity:
the allocation must describe resources only these agent jobs use.

## Check a host

On the host, from a checkout of your repository:

```bash
II_OS_AGENT_HOST_ID=acme-agent-host II_OS_AGENT_STATE_DIR=/srv/ii-os-agent \
  PYTHONPATH=scripts/agent python3 -m providers.runtime_ticket preflight
```
