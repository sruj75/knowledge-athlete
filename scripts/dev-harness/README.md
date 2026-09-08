# Local development harness

Use a standard macOS account for coding agents and Dev, with your personal account reserved for everyday Beta and release credentials. Source, profiles and credentials belong in the private account home; generated SwiftPM output may live on an explicitly selected external cache volume.

## Conductor and installation

- **Separate Dev account:** run coding agents and named apps under a standard macOS account; keep everyday Beta and release credentials in the personal account. Conductor worktrees alone do not isolate same-user processes or data. `OMI_DEV_APP_ROOT="$HOME/Applications"` makes `run.sh`, `omi-dev`, and the harness install/track the same user-owned app; only this root and `/Applications` are accepted. Existing recorded system installs remain stoppable after changing the preference.

- **Conductor controls:** `.conductor/settings.toml` wires Setup, Dev, Status, and Archive to `scripts/dev-harness/conductor-dev.sh`; use Conductor's Stop button on the foreground Dev command. Start allocates a private internal session temp directory so Firebase cannot discover another workspace's same-project hub during failed-start export. Stop/Archive drain only the existing harness's recorded owners and preserve profiles/history. New workspaces copy no env files or release secrets and default to offline providers. Configure only Dev provider keys to opt into real mode. Shared settings take effect after merge; use repository-local settings for an unmerged setup.

- **Generated build storage:** optionally set `OMI_DEV_CACHE_ROOT` before Conductor Setup to an absolute cache directory whose parent already exists (for example `/Volumes/T9/IntentiveDevBuilds`). Setup links only a fresh `Desktop/.build` to a UID/worktree-specific cache, under the build lock; existing build trees are preserved for explicit inspection. Keep source, credentials, auth temp files, and persistent data in the private internal home. Do not globally redirect `TMPDIR` or rely on an ownership-disabled external disk for privacy.

## Process and data ownership

- **Workspace ownership.** `scripts/dev-instance.sh` owns `omi-<worktree>` plus nine Conductor ports; `OMI_HARNESS_PORT_OFFSET` preserves qualification. Foreign listeners fail closed. `make desktop-run-local` records exact launch-attempt/token/PID/start/bundle/profile/bridge ownership; `make dev-status` checks it and `make dev-down` stops only those processes. Incomplete registration/stops retain evidence. After exact TERM, passive drain accepts macOS argv loss only for the same PID/start; KILL revalidates full provenance. Permission reopens keep the bundled port; successor recovery requires prior ownership plus exact executable/source/bridge, never app-name adoption. Provider/admin secrets stay in the backend. Embedded `OMI_LOCAL_PROVIDER_MODE`: absent/invalid is offline; explicit real AI still uses local accounts/storage.

Account separation must be verified under the actual Dev login. A same-user named bundle is operational isolation only; it does not restrict an unrestricted agent's filesystem or process permissions. Existing agents stay under their current UID until they are moved. A Dev launch or restart test does not qualify a signed Beta download or Sparkle update.

## Commands

```bash
# In a fresh linked worktree under the Dev account:
OMI_DEV_CACHE_ROOT=/Volumes/T9/IntentiveDevBuilds bash scripts/dev-harness/conductor-dev.sh setup
bash scripts/dev-harness/conductor-dev.sh start
# Conductor Stop / terminal Ctrl+C ends the foreground Dev command and drains its services.
bash scripts/dev-harness/conductor-dev.sh status
```

`start` defaults to offline providers and synthetic local accounts. To use real providers, configure only Dev-scoped keys in the private `backend/.env.local-dev`, then explicitly use `PROVIDER_MODE=real`. Dev and Beta continue to have separate app identities and data locations.

The setup preserves an existing `.build` instead of silently moving or deleting it. Archive stops the workspace's owned processes; it retains persistent profiles, evidence, and generated caches for later liveness-checked cleanup.
