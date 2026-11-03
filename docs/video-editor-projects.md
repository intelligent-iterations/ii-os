# Video editor projects and workspace renders

The video editor stores a bounded project document and up to 50 numbered
revision documents in the workspace. Project lists load once when a person
opens the editor, and project reads, saves, deletes, revision restores, media
loads, and workspace renders happen only after that person asks for them.
There is no passive listener, background feed refresh, or recurring schedule.
A render explicitly started by a person checks only its own persisted job at
the shared active-operation cadence until completion, failure, cancellation,
disposal, or the render workflow's timeout plus five minutes.

## Timeline compatibility contract

ii-os owns the durable project document and its open/save behavior. The
`ii_flutter_video_editor` package owns the in-memory editing model, while the
Functions API stores a bounded timeline map opaquely and does not migrate it.

Every released integer timeline version is an immutable field contract. A
field addition, removal, meaning change, or requiredness change must increment
the version. Each version uses exact key allowlists; an unknown same-version
field is rejected because accepting it and later emitting canonical JSON would
silently erase data the current build does not understand. Version 1 support
therefore means canonical documents emitted by the released v1 encoder, not
every partial map the former decoder happened to default.

Every released version remains readable until a separately approved
deprecation provides export, backup, rollback, and recovery. Migration steps
are pure, deterministic, adjacent, additive transformations that preserve
media references and perform no I/O or media rewrite. Opening prepares and
decodes only in memory: it does not write back, mark the project dirty, or add
history. The next explicit save emits the current canonical version.
Destructive conversion and automatic migration writeback are not authorized.

Each supported `vN` has frozen `project.json`, `expected-current.json`, and
`provenance.json` fixtures. Provenance records the classification, producer
commit and date, codec digest, declared sibling package revision, construction
method, verification command, file digests, supported claims, and non-claims.
Synthetic fixtures prove schema plumbing only; real media, platform, and
provider claims require captured evidence at those boundaries.

### Decoded stream timing

Saved media records may carry independent `videoTiming` and `audioTiming`
envelopes. Each envelope has exactly `presentationStartMicros` and
`durationMicros`: the start is nonnegative relative to the earliest selected
stream, and the duration is positive. When decoded timing is present, every
selected stream has an envelope, the earliest start is zero, and the latest
end equals the media record's duration. The fields may all be absent so
projects saved before decoded timing existed remain readable; those legacy
records reopen with the former zero-start/full-duration approximation until
an explicit save backfills current decoded timing. A present malformed,
partial, overlong, or stream-inconsistent envelope is rejected rather than
defaulted. This media-record addition does not change the separate timeline-v1
field contract.

Media-record decoding and restore are target-neutral: an over-target project
must still reopen for controlled repair. Current browser/native limits apply at
import, edit admission, and render preflight rather than making persisted media
unreadable on a narrower device.

FFprobe selects the first video stream and first audio stream, matching the
editor compiler's stream selectors. Exact integer PTS and time-base metadata
take precedence, with finite positive stream and format durations as bounded
fallbacks. A container's common positive or negative presentation origin is
normalized away. The remaining inter-stream skew determines each linked
clip's timeline offset, while source ranges remain local to the first decoded
frame or sample so trims and splits cannot replay or truncate the stream.

The fixture under `test/fixtures/video_editor/media/linked-offset-v1/` is a
real MOV file generated entirely from FFmpeg's `color` and `sine` sources, with
no external media; its video starts at PTS 1.000 seconds and its audio at PTS
1.175 seconds. Its `provenance.json` records the exact generation and probe
commands and pins the media and probe digests. The process test probes,
places, splits, renders, and decodes it, then checks post-split pixels, the
audio gain marker, and the 175-millisecond onset. It does not claim attached-picture/default-stream
selection, encoder priming, or browser/mobile execution.

## Firestore read-cost budget

Counts below are Firestore document reads. Named databases receive no free
quota; multiply by your database location's current document-read price
([Cloud Firestore pricing](https://cloud.google.com/firestore/pricing)) to
estimate cost.

The project-list query has one equality field and a server-side `limit(100)`,
so it has no billed index-entry batches and costs at most 100 returned-document
reads, or the one-read empty-query minimum. Exact project and revision reads
use document ids. The Admin SDK adds no Security Rules reads. Access checks are
included below as one membership, one workspace, and one organization read.
Transactions use one attempt normally and a conservative maximum of five.

Media operations are included because opening and saving a project can fan out
to existing bounded source-asset and artifact-grant paths. A project has at
most 32 media records and a workspace render has at most 12 inputs. The
conservative per-operation envelopes include connection lookup, record reads,
retention hold/release reads, transaction retries, and source-asset upload
completion; cached media grants can only reduce them.

| Explicit operation | Expected reads | Worst-case reads |
| --- | ---: | ---: |
| Open editor and list 20 / at most 100 projects | 23 | 103 |
| Create a project | 3 | 3 |
| Open a project with 4 / at most 32 media records | 40 | 260 |
| Save with 4 held, 1 new, and 1 removed / replace all 32 | 56 | 1,228 |
| Delete a project with 4 / at most 32 media records | 26 | 294 |
| Read one numbered revision | 5 | 5 |
| Dispatch, track, and clear one workspace render | 703 | 39,928 |

The render watcher uses `IiOsPollingCostPolicy.activeOperation` at one request
every two seconds and permits only one watched job per editor ViewModel. Each
active job-detail request reads one membership, two workspace documents, two
organization documents, the job before and after reconciliation, one raw job
record, and one transaction read: 9 expected reads. The worst case allows five
transaction attempts, for 13 reads. A terminal request skips reconciliation
and costs 7 reads.

An illustrative two-minute render makes 60 active checks, one terminal check,
and one ordinary project save to clear its persisted job id. Including dispatch
gives `100 + (60 × 9) + 7 + 56 = 703` reads. The worst-case envelope uses the
95-minute client deadline, 2,861 checks including ten reconnect-immediate
checks, 13 reads per check, the 1,500-read dispatch envelope, a 7-read terminal
check, and the 1,228-read project-save envelope: `(2,861 × 13) + 1,500 + 7 +
1,228 = 39,928` reads. There are no index-entry reads, Security Rules dependent
reads, snapshot reconnects, or collection queries on this path. Push
notification delivery was considered, but it cannot be the sole completion
signal because browser permission and transport are optional; the bounded
exact-job check is the reliable fallback.

An illustrative workload of ten active editors, each month opening the editor
20 times, opening ten projects, saving ten times, creating two projects, deleting
one, reading two revisions, and dispatching two workspace renders:

```text
list:      10 × 20 × 23  =  4,600 reads/month
open:      10 × 10 × 40  =  4,000 reads/month
save:      10 × 10 × 56  =  5,600 reads/month
create:    10 ×  2 ×  3  =     60 reads/month
delete:    10 ×  1 × 26  =    260 reads/month
revision:  10 ×  2 ×  5  =    100 reads/month
render:    10 ×  2 × 703 = 14,060 reads/month
total                       28,680 reads/month
```

The fail-closed stress envelope assumes 20 editors perform each operation 30
times per day for 30 days, every project and render reaches its media/input
limit, and every transaction reaches five attempts:

```text
list:      20 × 30 × 30 ×   103 =  1,854,000 reads/month
open:      20 × 30 × 30 ×   260 =  4,680,000 reads/month
save:      20 × 30 × 30 × 1,228 = 22,104,000 reads/month
create:    20 × 30 × 30 ×     3 =     54,000 reads/month
delete:    20 × 30 × 30 ×   294 =  5,292,000 reads/month
revision:  20 × 30 × 30 ×     5 =     90,000 reads/month
render:    20 × 30 × 30 × 39,928 = 718,704,000 reads/month
total                                    752,778,000 reads/month
```

The worst case is an abuse envelope, not expected traffic. Loading the list
only when the editor opens, loading media only when a project is selected,
reusing immutable media grants, and retaining numbered revisions instead of
querying history are cheaper than listeners, eager media loading, or any
passive polling. A render watcher that keeps reading after a terminal job state
or past the 95-minute client deadline is a defect. Raising any limit or adding
passive refresh changes these bounds; recompute this budget.
