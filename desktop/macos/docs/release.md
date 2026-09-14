# Desktop release

The owner Beta release path is operational. On 2026-09-12, Codemagic built and published
signed/notarized `v0.0.4+4-macos`; owner-manual qualification admitted the exact artifacts, Beta
promotion completed, and the installed owner app later updated from 0.0.3 to 0.0.4 through
Sparkle. This dated receipt proves the owned Beta machinery and credentials, not any later source
or candidate. Stable and Preview remain deferred. See the complete checklist in
[`../../../OWNER-PROVIDER-DECISIONS.md`](../../../OWNER-PROVIDER-DECISIONS.md).

Each Beta repair follows the same deliberate path: after the repair reaches `main` and its
exact-SHA release checks pass, a maintainer runs `Build Desktop Release Candidate`. The planner
binds one immutable `v*-macos` tag to the exact admitted `main` SHA, the owned Codemagic tag
workflow builds and publishes signed candidate assets, and owner-manual qualification admits the
exact digests before Beta promotion. There is no push or schedule trigger that creates candidates
automatically.

For bounded, read-only candidate status polling, run from the repository root:

```bash
python3 .github/scripts/plan-desktop-release.py \
  --repository sruj75/knowledge-athlete \
  --watch-source-sha <40-character-source-sha> \
  --watch-max-polls 5 \
  --watch-poll-seconds 30
```

The watcher reports only lifecycle transitions and never creates tags or builds, dispatches qualification, promotes channels, or changes release pointers.

If a signed, qualified candidate did not reach Beta, run **Recover Qualified Desktop Beta** with `release_tag`, `confirm=recover-beta`, and a short `reason`. The backend rechecks immutable evidence, qualification, admission state, and the pointer transaction; the workflow run is the recovery audit record.

To make that exact current Beta candidate Stable, run **Promote Qualified Desktop Stable**
with `release_tag` and `confirm=promote-stable` only after the owner gives fresh publication
authorization. It reads the current pointer, uses its generation for the atomic transition,
and verifies the published pointer, hashes, and appcast. It only changes the desktop Stable
channel; backend production deployment remains a separate approval plane.

Do not edit release bodies, pointers, static routes, or legacy bridges manually.
