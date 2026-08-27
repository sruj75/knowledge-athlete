# Desktop release

No Intentive release lane is executable yet. Repository-safe S-29 work owns the bundle,
artifact, GitHub, signed-smoke, libwebp, and qualification contracts, but candidate creation
remains blocked until an owned root `codemagic.yaml`, Codemagic application/workflow IDs,
Apple/notarization/Sparkle secrets, release GitHub App, trusted runner, and production
backend/feed are configured. See the complete checklist in
[`../../../OWNER-PROVIDER-DECISIONS.md`](../../../OWNER-PROVIDER-DECISIONS.md).

After those blockers are closed, the intended normal path is deliberate and manual: a
maintainer runs `Build Desktop Release Candidate`, the planner binds one immutable
`v*-macos` tag to the exact admitted `main` SHA, the owned Codemagic tag workflow builds and
publishes signed candidate assets, the trusted Intentive M1 lane qualifies the exact digests,
and only then may the backend advance Beta. There is no push or schedule trigger that creates
candidates automatically.

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
