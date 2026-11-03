# Deployment boundary

ii-os does not ship an active deployment workflow. Operators copy and review
the inert examples under `examples/workflows/`, then bind them to their own
hosting project, repository variables, secrets, and cost controls.

Keep these values in the implementation repository or deployment platform,
never in the public source repository:

- cloud project, database, bucket, and service-account identifiers;
- GitHub organization, repository, environment, and runner topology;
- signing identities, mobile application IDs, and store credentials;
- secret names when they reveal private topology, and all secret values;
- production smoke-test identities, runbooks, migrations, and incident notes.

The source defaults are intentionally generic. Cross-repository agent
publication is disabled unless `II_OS_AGENT_COORDINATOR_REPOSITORY` and
`II_OS_AGENT_PUBLICATION_TARGETS` explicitly allow the exact repositories.
Agent execution additionally requires the implementation-owned
`II_OS_AGENT_TRUSTED_SOURCE_MANIFEST_BASE64`. Mobile update dispatch stays
disabled unless the implementation supplies `II_OS_MOBILE_UPDATE_REPOSITORY`.
Song render choices use provider-neutral defaults and may be replaced with a
validated `II_OS_SONG_RENDER_PROFILES_JSON` list owned by the implementation.

Before enabling a copied workflow, calculate its expected and worst-case
runner, cloud, storage, transfer, and retry costs. Add bounded concurrency,
timeouts, retry limits, and a terminal cleanup step appropriate to your
provider.

The repository's own quality, CodeQL, and Scorecard workflows are deliberately
limited to standard GitHub-hosted Linux runners in a public repository. They
upload no Actions artifacts, create no caches, call no cloud or model provider,
and have per-job timeouts. Under GitHub's public-standard-runner terms their
expected and worst-case GitHub charge is $0. Larger runners, private-repository
execution, artifacts, caches, Packages, and deployment are outside that
approved envelope and remain disabled.
