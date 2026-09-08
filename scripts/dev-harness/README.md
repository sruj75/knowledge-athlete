# Local development harness

Run Conductor, coding agents, and named Dev apps in the same logged-in macOS account as everyday Intentive Beta. Beta must be able to observe the desktop where the user is working on Intentive itself. No account switch or separate `toxy` login is required.

Beta is the installed, provider-built app shared with friends. Dev is a separate named app built from a worktree. Local edits and builds update only Dev; a qualified published Beta release reaches the user's Beta and friends through the Beta update channel.

## Conductor and installation

- **Side-by-side apps:** keep Beta installed through its signed download/update flow. `OMI_DEV_APP_ROOT="$HOME/Applications"` makes `run.sh`, `omi-dev`, and the harness install/track a separate named Dev app in the current account; only this root and `/Applications` are accepted. Dev never uses a Stable/Beta bundle identity. Existing recorded system installs remain stoppable after changing the preference.

- **Conductor controls:** `.conductor/settings.toml` wires Setup, Dev, Status, and Archive to `scripts/dev-harness/conductor-dev.sh`; use Conductor's Stop button on the foreground Dev command. Start allocates a private internal session temp directory so Firebase cannot discover another workspace's same-project hub during failed-start export. Stop/Archive drain only the existing harness's recorded owners and preserve profiles/history. New workspaces copy no env files or release secrets and default to offline providers. Configure only Dev provider keys to opt into real mode. Shared settings take effect after merge; use repository-local settings for an unmerged setup.

- **Generated build storage:** optionally set `OMI_DEV_CACHE_ROOT` before Conductor Setup to an absolute cache directory whose parent already exists (for example `/Volumes/T9/IntentiveDevBuilds`). Setup links only a fresh `Desktop/.build` to a UID/worktree-specific cache, under the build lock; existing build trees are preserved for explicit inspection. Keep credentials, auth temp files, and personal Beta data in the private internal home. Do not globally redirect `TMPDIR` or rely on an ownership-disabled external disk for privacy.

## Process and data ownership

- **Workspace ownership.** `scripts/dev-instance.sh` owns `omi-<worktree>` plus nine Conductor ports; `OMI_HARNESS_PORT_OFFSET` preserves qualification. Foreign listeners fail closed. `make desktop-run-local` records exact launch-attempt/token/PID/start/bundle/profile/bridge ownership; `make dev-status` checks it and `make dev-down` stops only those processes. Incomplete registration/stops retain evidence. After exact TERM, passive drain accepts macOS argv loss only for the same PID/start; KILL revalidates full provenance. Permission reopens keep the bundled port; successor recovery requires prior ownership plus exact executable/source/bridge, never app-name adoption. Provider/admin secrets stay in the backend. Embedded `OMI_LOCAL_PROVIDER_MODE`: absent/invalid is offline; explicit real AI still uses local accounts/storage.

- **Personal and test data:** Beta retains its own login, history, preferences, Keychain namespace, and hosted backend. Dev uses bundle-scoped state and local Firebase/Redis with synthetic accounts by default, including when real AI providers are explicitly enabled. Never seed Dev from Beta, copy Beta credentials into a workspace, or point routine Dev at the shared Beta backend.
- **Using Beta while coding:** keep Beta running during development. Use Dev's semantic automation bridge for routine tests so the cursor stays available to the user. Enable Dev screen capture, microphone capture, and interventions only for deliberate tests through the app's existing controls; permission and capture behavior still need live verification. Never stop Beta to make a Dev test pass.

This is app/process/data separation for ordinary development. An unrestricted agent under the same macOS user still has that user's filesystem and process permissions; worktrees and bundle names are not an OS security sandbox. Keep this limitation explicit without requiring a separate desktop login.

Coexistence qualification must run with the actual signed Beta installed: record its process identity and user-visible state, start/stop/restart Dev, and verify Beta remains running with its login/history/settings intact. If Beta is unavailable, record that qualification as pending. A Dev-only restart test does not qualify Beta coexistence or a Sparkle A-to-B update.

## Commands

```bash
# In a fresh linked worktree in the user's current desktop account:
OMI_DEV_CACHE_ROOT=/Volumes/T9/IntentiveDevBuilds bash scripts/dev-harness/conductor-dev.sh setup
bash scripts/dev-harness/conductor-dev.sh start
# Conductor Stop / terminal Ctrl+C ends the foreground Dev command and drains its services.
bash scripts/dev-harness/conductor-dev.sh status
```

`start` defaults to offline providers and synthetic local accounts. To use real providers, configure only Dev-scoped keys in the private `backend/.env.local-dev`, then explicitly use `PROVIDER_MODE=real`. Dev and Beta continue to have separate app identities and data locations.

The setup preserves an existing `.build` instead of silently moving or deleting it. Archive stops the workspace's owned processes; it retains persistent profiles, evidence, and generated caches for later liveness-checked cleanup.
