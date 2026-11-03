# Organization people and workspace access

The People page is the organization directory and the place an Organization
Admin assigns projects. Organization membership and workspace access remain
separate: an existing organization member receives a workspace immediately,
while a new person receives an email invitation that may carry initial
workspace grants.

The directory GET is user-started and bounded to 100 members, 100 workspaces,
and 100 live invitations. It never loads the member-by-workspace matrix.
Opening one person's access dialog starts a second bounded GET for at most 100
workspace memberships. Toggling a workspace is an explicit mutation; there is
no listener, reconnect refresh, poll, recurring timer, or scheduled read.

Organization standing is editable independently of project access. A person
may therefore be an Admin in one workspace, an Editor in another, and a Viewer
in a third. Workspace roles define capability ceilings; the editor selects the
claims inside that ceiling and can grant only capabilities the editor already
holds in that workspace. Only the corresponding owner can assign or remove an
Owner role, and neither organization nor workspace mutations may remove the
last owner.

Removing a person deletes their organization membership and every workspace
membership in that organization in one transaction. Deleting an organization
is owner-only. It removes the organization root, workspace roots, organization
memberships, and workspace memberships, and revokes pending invitations.
Deletion first records an atomic in-progress marker while preserving the
deleting owner's membership. Invitation acceptance, new invitations, member
changes, workspace grants, and workspace creation then fail closed, preventing
a concurrent request from recreating access after the cascade has read it. An
interrupted cascade can be retried by a live Owner; the Owner and root are
removed together only in the final batch.
External cloud resources, Secret Manager values, generated media, job history,
and audit history are intentionally outside that deletion boundary.

## Firestore read-cost budget

Counts below are Firestore document reads. Named databases receive no free
quota; multiply by your database location's current document-read price
([Cloud Firestore pricing](https://cloud.google.com/firestore/pricing)) to
estimate cost.

Every read is terminal and user-started. There is no listener, reconnect
refresh, poll, recurring timer, or scheduled read. The server uses the Admin
SDK, so Security Rules add no dependent reads. The queries use equality
filters, or equality filters with one ordered field, and therefore add no
billed index-entry batches under the current pricing rule. Missing point reads
and empty queries are conservatively counted as one read.

The hard limits are applied before an unbounded result can execute: 100
organization members, 100 workspaces, 100 workspace grants for one person, 100
workspace members for a permission edit, 100 pending invitations, and 10,000
workspace grants for an organization deletion. A member removal reads at most
two owner rows for each workspace the target owns. Results above a limit fail
closed. Transaction worst cases assume five attempts.

| Terminal operation | Expected reads | Worst-case reads |
| --- | ---: | ---: |
| Directory GET (20 members, 10 workspaces, 5 invitations) | 36 | 304 |
| One person's workspace-access GET (10 assignments) | 12 | 103 |
| Workspace access on/off mutation | 5 | 21 |
| Organization role edit | 22 | 511 |
| Workspace role/capability edit | 21 | 506 |
| Member removal, including workspace-owner checks | 34 | 2,016 |
| Invitation acceptance with 1 expected / 20 maximum grants | 4 | 115 |
| Organization deletion (20 members, 10 workspaces, 20 grants, 5 invitations) | 58 | 10,315 |

The organization deletion maximum is one caller-membership point read, five
attempts of the two-read deletion-claim transaction, and capped query results
of 101 organization members, 101 workspaces, 10,001 workspace grants, and 101
pending invitations. Bulk and batch writes add no reads. Even if 100
maximum-size deletions are each retried as a whole once by a user, the read
count is:

```text
100 × 2 × 10,315 = 2,063,000 reads
```

An illustrative month assumes ten organizations, five admins each, 30 explicit
page loads and five access-dialog opens per load, 500 access toggles, 200
organization-role edits, 500 workspace-permission edits, 200 member removals,
200 invitation acceptances, and ten organization deletions:

```text
directory:             10 × 5 × 30 × 36       =  54,000
access dialogs:        10 × 5 × 30 × 5 × 12   =  90,000
access toggles:        500 × 5                 =   2,500
organization edits:   200 × 22                =   4,400
workspace edits:      500 × 21                =  10,500
member removals:      200 × 34                =   6,800
invitation accepts:   200 × 4                 =     800
organization deletes: 10 × 58                 =     580
total                                             169,580 reads/month
```

The fail-closed abuse envelope starts from a 402,300,000-read directory,
dialog, and toggle ceiling, then adds 100,000 maximum-retry organization edits,
workspace edits, member removals, and invitation accepts plus 100 maximum-size
deletions:

```text
directory/dialog/toggle: 402,300,000
organization edits:      100,000 × 511 =  51,100,000
workspace edits:         100,000 × 506 =  50,600,000
member removals:       100,000 × 2,016 = 201,600,000
invitation accepts:      100,000 × 115 =  11,500,000
organization deletes:        100 × 10,315 = 1,031,500
total                                      718,131,500 reads/month
```

The maximum is an abuse envelope, not expected traffic. The cheaper
alternative remains loading one selected person's bounded assignments instead
of a member-by-workspace matrix. Raising any limit or adding passive refresh
changes these bounds; recompute this budget.
