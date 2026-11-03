# Workshop agent deployment state

The Workshop board projects one server-owned deployment receipt. GitHub
workflow state and runner lifecycle state are separate phases; the UI says
`Agent working` only while the runner reports the agent running (phase
`fleet_running` or `execution_running`). Queueing, submission, cleanup, and
finalization have their own labels. A stale phase becomes deployable only after
its safety deadline and after the exact prior workflow is stopped or an unbound
dispatch is observed absent.

Agent execution requires an external runner control plane that accepts job
requests, leases disposable runtimes, and reports their lifecycle; it is not
part of this repository. Fleet is Intelligent Iterations' implementation of
that contract, which is why some phase and field names carry its name.

## Target branch

Agents currently target a fixed `dev` branch in each connected repository.
Readiness reads `refs/heads/dev`, agent permission profiles are read from and
installed on `dev`, agent pull requests must use `dev` as their base, and the
QA handoff below reads Deployments in the `dev` environment. A repository
therefore needs a `dev` branch before agents can work in it. The branch name
is expected to become configurable per repository; until then, changing it
means changing those checks together.

## Recovery

Recovery is race-safe at the data boundary:

1. ii-os identifies the prior run by stored run id, or discovers an unbound run
   by exact title, actor, workflow, ref, SHA, and dispatch time.
2. An observed run is cancelled and then reread as completed.
3. The activation transaction rereads both the activation and dispatch
   documents and accepts only proof for their still-current identity.
4. Only after that transaction commits may the GitHub Project item return to
   `Todo`. A late callback changes the receipt or fails the new claim identity;
   either result prevents it from becoming the new deployment.
5. The trusted work-ticket workflow uses a per-project-item concurrency group,
   so a replacement also cancels any late unbound workflow before two copies
   can run.

Legacy runner recovery eligibility uses the existing three-hour lifecycle and
thirty-minute finalization deadlines in both the receipt projection and human
reset/review policy. Eligibility does not assert resource cleanup or bypass the
exact workflow-stop proof. A recorded agent-runtime execution never ages into
legacy recovery; unresolved or mixed execution states retain their lock until
the appropriate runtime result and cleanup are reconciled.

Failed QA always starts a new human-reviewed pass. `QA failed` and `QA failed
refinement` take precedence over any pull request recorded by an earlier pass,
so the ticket exposes `Review & redeploy` and retains that pull request only as
history. The same rule applies when a person edits a `Todo` or `Needs Human
Input` brief after finalization: the activation's immutable
`ticketBodyDigest` must match the current canonical ticket body before its
result can unlock the QA handoff. A missing or different digest fails closed
to a new Deploy action, and the API independently rejects a stale direct
status transition.

## Release deployment and QA handoff

The agent deployment receipt above does not prove that merged product code is
live. The repository's deployment pipeline must record each release as a
GitHub Deployment in the `dev` environment. A pipeline may converge a burst of
merges on the newest `dev` commit rather than deploying every merge commit
separately, so ii-os enables `Ready for QA` only after an explicit pull-request
read observes a successful current `dev` Deployment and GitHub proves that its
deployed commit is either the pull request merge commit or a descendant of it.
A merged pull request, branch name, runner job completion, release tag,
unrelated successful commit, or diverged deployment is not sufficient proof.
GitHub is authoritative for this user-facing QA gate because its Deployment
status covers the complete environment-scoped deployment job.

The read path is terminal, bounded, and cached. One selected pull-request load
reads the pull request. On a deployment-proof cache miss, a merged pull request
performs one `dev` Deployment list request (one result maximum), one status
list request (ten results maximum), and, only when the deployed SHA differs
from the merge SHA, one compare request. Each of those metadata requests has
a four-second timeout. The proof cache is isolated by
workspace, GitHub installation, repository, and merge SHA; it has a five-minute
TTL, a 256-entry LRU ceiling per warm API instance, and collapses concurrent
loads for the same key. A cache hit performs no Deployment, status, or compare
request. The existing Refresh PR action remains the only human-triggered reread.
There is no listener, poll, recurring schedule, cache warmer, Firestore cache,
or background refresh.

### Deployment-proof cost and request envelope

GitHub App installation REST reads have no monetary SKU; GitHub documents a
minimum primary limit of 5,000 requests per installation per hour, while most
REST `GET` requests consume one secondary-rate-limit point. The shipped
function configuration runs the Firebase HTTP API as a request-billed Cloud Run
function in `us-central1`, capped at six instances, concurrency 40, and 60
seconds. The proof path raises no invocation, instance, memory, CPU, timeout,
storage, log, Firestore, deployment, or recurring-work ceiling. Pricing
references:
[GitHub REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
and [Cloud Run pricing](https://cloud.google.com/run/pricing).

One cold coalesced-deployment proof costs three bounded GitHub metadata reads;
an exact deployment costs two; a cache hit costs zero. For an illustrative
workload of 100 explicit pull-request loads per month in each of 20 workspaces,
the conservative all-cold total is 2,000 × 3 = 6,000 GitHub reads per month.
For a stress envelope of 1,000 loads per month in each of 50 workspaces, it is
50,000 × 3 = 150,000 reads per month. For one installation
with the Project page's maximum 100 visible items, the five-minute TTL permits
at most 100 × 3 × 12 = 3,600 deployment-evidence reads per hour through the
cached path, below GitHub's 5,000-request primary limit before normal shared
installation traffic. Responses are control-plane JSON: one Deployment plus
ten statuses, or one comparison. No asset body is fetched or retained.

The Firebase second-generation default for this function is one vCPU and 256
MiB. A coalesced proof adds the status and compare calls beyond an exact-SHA
proof: one expected billable second, or eight timeout-bounded seconds worst
case. The illustrative workload above therefore adds at most 2,000 × 1 = 2,000
billable seconds expected and 50,000 × 8 = 400,000 worst case per month,
conservatively assuming every load is cold and receives no free tier or
concurrency sharing. Multiply those seconds by your region's current Cloud Run
vCPU-second price plus 0.25 × its GiB-second price to estimate cost. Exact-SHA
proofs need no compare request. The configured invocation, instance, and
60-second API ceilings do not increase. The cache is process-local and expires
automatically, so it needs no data migration or cleanup.

Deployments read-only is advisory for GitHub setup and agent dispatch. A
missing App or workspace grant appears as a visible recommendation and does not
block either. It still leaves the `Ready for QA` action unavailable, because a
non-blocking setup warning is not evidence that a release reached `dev`.

A permission profile that lacks the required `linux-amd64` capability fails
readiness closed. ii-os trusts only the lifecycle reporter and the exact
reviewed workflow blobs in its source manifest, so Deploy cannot claim
readiness against a mismatched workflow contract.

## Firestore read budget

Counts below are Firestore document reads. Named databases receive no free
quota; multiply by your database location's current document-read price
([Cloud Firestore pricing](https://cloud.google.com/firestore/pricing)) to
estimate cost.

There are no Firestore collection queries, index-entry reads, security-rule
dependent reads, listeners, reconnects, background polling, or recurring
schedules in this path. The Workshop board first receives GitHub's bounded
page of at most 100 Project items, then uses one concurrent `getAll` per receipt
collection for only those exact item ids. Missing receipts are billed document
reads, so one explicit board load costs two reads per visible item and is
bounded at 200 reads before either request executes. Deployment and recovery
reads are exact documents from the terminal human-started action. Transaction
worst cases assume five attempts.

| Human-started operation | Expected reads | Worst-case reads |
| --- | ---: | ---: |
| Explicit board load (25 expected / 100 maximum visible items) | 50 | 200 |
| Existing board, readiness, activation, and dispatch path | 18 | 45 |
| Recovery validation and atomic state transitions | 8 | 40 |
| Five lifecycle callbacks, two exact documents each | 10 | 50 |
| Total successful recovery deployment | 36 | 135 |

Five recovery deployments cost 180 expected reads and 675 worst-case reads.
Including one board load at the 25-item expected size or the 100-item hard
maximum gives 230 expected reads and 875 worst-case reads. An illustrative
workload of 100 explicit board loads and 100 deployments per month in each of
20 workspaces totals 172,000 reads per month. A stress envelope of 1,000
maximum-size board loads and 1,000 recovery deployments per month in each of
50 workspaces is 16,750,000 reads per month. Volume is exactly proportional to
explicit page loads and Deploy clicks and has no passive cadence; raising a
limit or adding passive refresh changes these bounds, so recompute this
budget.

The release-to-QA proof and exact-brief result check above add no Firestore
operation, so this arithmetic is unchanged. The board compares the ticket body
already returned by GitHub with the activation digest returned by its existing
bounded receipt read. The status endpoint reuses the digest from its existing
two-document pull-request lookup. Additional release evidence comes only from
the bounded GitHub REST reads described in that section.
