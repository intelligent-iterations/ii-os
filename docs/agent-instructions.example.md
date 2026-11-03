# Example contributor-agent instructions

This file is an optional starting point for a private implementation
repository. Do not copy it to the public repository root as `CLAUDE.md` or
`AGENTS.md`; public release candidates intentionally keep those root files
empty.

```markdown
# Project instructions

## Source boundary

- Reusable application and domain behavior belongs in the imported ii-os
  source repository.
- Environment identifiers, credential wiring, deployment workflows, and
  operator runbooks belong in this private implementation repository.
- Never commit secrets, local absolute paths, durable user state, or generated
  credentials.

## Development

- Work on a task branch from the latest target branch.
- Preserve unrelated and user-owned changes.
- Add tests for observable behavior and boundary changes.
- Run the Flutter and Functions analyzers and unit tests before merging.

## Deployment

- Pin the exact ii-os source revision.
- Keep cross-repository trust and publication targets explicit and fail closed.
- Bound runner time, concurrency, retries, cloud spend, and cleanup.
```

Add only rules that are true for your implementation. Keep changing
procedures in private runbooks and mechanically checked constraints in tests.
