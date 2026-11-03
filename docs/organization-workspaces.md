# Organization workspaces

## Model

An organization is the tenant. It owns bounded catalogs of customer GCP
projects, GitHub App installations, repository and permission envelopes, and
runner pools that are either managed by a runner control plane (provider
`fleet`) or customer-owned and maintained by hand (provider `customer`). A
workspace is a project inside that tenant. People receive organization
membership and an explicit grant to each workspace they may open.

Creating a sibling workspace creates only the workspace record and its
creator's workspace membership. It does not copy credentials and starts with
`resourceGrantVersion: 1` plus empty GCP, GitHub, and runner grants. Empty means
no access, never "inherit everything." An Organization Admin first adds
resources under **Organization resources**. A Workspace Admin or Organization
Admin then selects an explicit subset under **Workspace access**. A new
workspace with no grants routes to organization resource administration when
the catalog is empty, and to workspace subset selection when resources are
available.

For an already-running organization whose original workspace still owns the
legacy connection reference, **Use existing setup** promotes deterministic
organization catalog references without copying, rotating, or deleting a
credential. Before saving that ceiling, ii-os reads the exact permission set
GitHub currently grants the installation; it never substitutes a hard-coded
subset. Sibling creation performs the same promotion before creating the child
when a visible source workspace is available. An already-created empty child
can therefore recover from Organization resources without entering GCP or
GitHub credentials again.

An earlier resource-pool promotion stored only Actions, Contents, and Pull
requests on promoted legacy sources. A bounded compatibility reader recognizes
only that exact generated signature plus its original-source marker. When that
source has a configured Workshop Project, it restores Issues and Organization
projects in memory. It does not widen a sibling workspace or a customized
grant, and it does not rewrite the stored workspace.

New GCP projects use one-shot service-account bootstrap. The browser accepts a
Google service-account JSON paste or local `.json` file up to 64 KiB; the
control function validates a strict Google key shape, keeps it only in memory,
and uses it to discover bounded GCP resources plus organization-labelled GitHub
App secrets. Neither the key nor an administrator-authored connection document
is persisted, logged, cached, audited, or echoed. Failed checks return only
nonsecret status and remediation text.

The organization catalog is embedded on its already-read organization document
and is bounded at 20 resources per kind, 500 total repository names, and 700
KiB. A workspace may reference several resources, but exactly one selected
resource per nonempty kind is marked primary. The current runtime consumes that
primary GCP project and GitHub App. The ii-os dispatch boundary also requires
and records the primary runner grant; downstream runner placement does not yet
consume that recorded grant. Future per-operation selection may use additional
grants without changing ownership.

Every workspace GCP permission, GitHub permission, repository name, runner
capability, CPU limit, RAM limit, and concurrency limit is transactionally
checked as a subset of the current organization envelope. Organization resource
changes can make a grant stale but can never widen it. Runtime resolution
rejects stale grants before loading a key, minting a token, reading or writing
an asset, uploading a workflow artifact, or dispatching a job.

An **Organization Admin** manages organization membership, workspaces, GCP and
GitHub resources, runner pools, and organization audit state. A **Workspace
Admin** manages one workspace and may narrow its resource grants, but cannot add
or widen an organization resource. Other users continue to be scoped by their
explicit workspace memberships.

Runner capacity comes from the organization-scoped report of an external
runner control plane, not from the GCP credential. The control plane is not
part of this repository: ii-os expects one deployed alongside it that reports
its hosts, accepts job requests, and leases disposable runtimes. Fleet is
Intelligent Iterations' implementation of that contract, which is why the
provider value, the stored `fleetSnapshots` report, and the **Sync Fleet
capacity** action carry its name. Sync reads only a fresh provider attestation
and derives a conservative envelope from non-draining hosts: the union of
reported capabilities, the largest per-host CPU/RAM limits, and at most one
concurrent slot per eligible host. Sync never registers or creates a host.

Organizations produced by the earlier backfill may not yet have an explicit
`githubInstallationId` or repository boundary. The first user-started sibling
creation scans at most 201 workspaces in that organization, accepts only one
unique positive legacy installation ID, and freezes the union of already
selected repositories as the organization boundary. A conflict, more than 200
workspaces, or more than 500 repositories fails closed for manual resolution.
New organizations start with an explicit empty boundary, and resolved
organizations never pay for this scan.

That singular connection and installation representation is a compatibility
shim. It is deterministically exposed as one legacy GCP resource and one legacy
GitHub resource without copying the private key. New workspaces never enter the
shim, and the legacy workspace installation and repository editor is rejected
once explicit resource grants exist.

Direct workspace invitations remain available only to pre-organization
migration records. A tenanted workspace requires an organization invitation
with optional explicit workspace grants. At most 20 grants may ride on one
invitation, and each is checked against the organization when the invitation
is created and again inside its acceptance transaction.

Organization invitations send through the same verified ZeptoMail transport
as sign-in codes. HMAC-keyed Firestore windows allow at most one send to an
address per minute, five sends to an address per hour, and twenty sends from a
source IP per hour; an organization may have at most 100 live invitations.
Delivery failure leaves the invitation usable and records a failed status for
the People page instead of pretending that the message arrived.

## Firestore read-cost budget

Counts below are Firestore document reads. Named databases receive no free
quota; multiply by your database location's current document-read price
([Cloud Firestore pricing](https://cloud.google.com/firestore/pricing)) to
estimate cost.

The session route is bounded before execution at 200 workspace memberships and
100 organization memberships. With `W` visible workspaces, `Ow` distinct
workspace organizations, and `Om` tenant memberships, it reads:

```text
workspace membership query       W
workspace documents              W
workspace organization overlay   Ow
organization membership query    Om
organization documents           Om
total                             2W + Ow + 2Om
```

Equality-only membership queries do not incur billed index-entry batches, the
Admin SDK does not add security-rule dependent reads, and there are no
listeners, reconnect loops, or scheduled refreshes. Empty result queries have
the Firestore minimum one-document charge. A session loads on sign-in or page
startup and after an explicit user mutation or refresh; an idle page adds no
reads.

The resource catalog adds no document to this session arithmetic because it is
embedded in each organization document already counted above. There is no
listener, poller, scheduled refresh, subcollection fan-out, or client-side
slicing.

An illustrative workload of 100 accounts, 30 session loads per account per
month, 10 visible workspaces, and one organization per account:

```text
23 reads/load × 30 loads × 100 accounts = 69,000 reads/month
```

The fail-closed bounded worst case allows all 200 workspace grants to name
distinct organizations even if inconsistent legacy data omits matching
organization memberships. At the same 3,000 monthly loads it is:

```text
(2 × 200 + 200 + 2 × 100) × 3,000 = 2,400,000 reads/month
```

Creating a workspace in a resolved organization adds six direct reads: the
actor's organization membership, the organization installation record, the
organization and live actor membership in the creation transaction, the
created workspace, and its organization overlay. The transaction prevents a
workspace from racing into an organization deletion. The one-time legacy
GitHub-configuration promotion adds at most 201 workspace reads, for a
fail-closed maximum of 207 direct reads for one transaction attempt. The client
then performs its ordinary bounded post-mutation session load.

The replacement resource routes stay explicit and bounded, including their
authorization reads:

- saving a GCP or manually maintained customer runner resource reads one
  organization membership
  and one organization document in a transaction: 2 expected reads or 4 under
  a conservative three-attempt transaction assumption;
- GCP validation additionally performs three direct canary reads before the
  organization write, so it is 5 expected reads or 7 with three transaction
  attempts;
- saving workspace grants as a Workspace Admin reads the workspace and its
  organization overlay, workspace membership, then the workspace and
  organization in one transaction: 5 expected reads or 9 with three attempts.
  An Organization Admin without workspace access adds one organization
  membership read, for 6 expected or 10 under the same retry assumption;
- explicitly opening the organization resource endpoint reads one organization
  membership and one organization document; the normal page uses the catalog
  already present in the session;
- promoting an existing workspace reads one organization membership, the
  source workspace and its organization twice while resolving and verifying
  the customer GitHub App, then the organization and named source workspace in
  a transaction: 7 expected reads, or 11 with three transaction attempts;
- syncing runner capacity reads one organization membership, one bounded
  control-plane snapshot document, and one organization document in a
  transaction: 3 expected reads, or 5 with three transaction attempts.

Each successful mutation is followed by the ordinary bounded session refresh.
Assuming 100 additional resource mutations per month, all taking the
seven-read legacy-promotion path, adds at most
`100 × (7 mutation reads + 23 refresh reads) = 3,000` expected reads. The
expected total becomes 72,000 reads. At an intentionally high operational bound
of 10,000 catalog mutations and 10,000 Organization Admin grant mutations,
conservative retries add at most `10,000 × (4 + 10) = 140,000` reads. Combined
with the bounded 2.4-million-read session case, that is 2.54 million reads.

Creating an organization invitation costs
`workspace grants + member lookup + invitation history + 2 rate-limit
documents + 2 access/context + 1 organization-deletion guard` reads. With one
grant, five invitation-history rows, and one attempt of each transaction the
expected count is 12. The limits make the conservative five-attempt worst case
539 reads: 20 grant documents, one member-query minimum, 501 history rows, two
context reads, ten rate-limit transaction reads, and five deletion-guard reads.
Acceptance reads the invitation, organization, prospective organization
membership, and at most 20 workspace grants in a transaction: 4 reads for the
expected one-grant case, 23 for one maximum-size attempt, and at most 69 under
a conservative three-attempt transaction retry assumption. Invitation
discovery is capped at 100 returned documents.

Even combining the stated worst-case session load with 100 worst-case invite
creates and 100 three-attempt acceptances is 2,460,800 reads.

### Organization-inherited workflow credentials

A workflow invocation is terminal and user-started. It adds no listener,
scheduled refresh, query, index-entry scan, client-side slice, or Security
Rules-dependent read.

The credential authentication path reads one token document transactionally,
then the issuing workspace and its organization overlay: 3 expected reads or
7 reads if the transaction makes five attempts. The claim's changed
authorization boundary point-reads one job, reads the target workspace and its
organization overlay, reads the job in the claim transaction, and reads the
recorded result: 5 expected reads or 9 with five transaction attempts. These
are the same bounded reads made without organization inheritance; inheritance
selects the job's workspace for the existing workspace reads and copies the
already-loaded `organizationId` into new token and job writes.

Incremental read arithmetic is therefore `0 added reads/run × any number of
runs, retries, clients, or workspaces = 0 added reads/month`.
Expected and worst-case read totals are unchanged. A legacy token derives its
organization from the issuing workspace already read during authentication;
there is no backfill query, rotation requirement, or compatibility poll.

## Verification

- The Firebase emulator proof covers fresh-account isolation, sibling creation,
  legacy organization promotion, a new sibling with no implicit access,
  explicit subset selection, resolved organization connection and installation,
  explicit membership, cross-organization grant refusal, and invitation
  acceptance.
- The backend unit suite proves catalog bounds, multiple resource kinds,
  workspace subset rejection, primary selection, and exact GitHub token scope.
- Routed-page goldens cover both administration surfaces, and ViewModel tests
  exercise mutations without Firebase or a widget tree.
- The expected session slope is 23 document reads for the stated
  10-workspace/one-org case; sustained read growth inconsistent with explicit
  user actions indicates a regression.
- These routes never delete or move an existing workspace, media object,
  membership, connection, or resource catalog entry.
