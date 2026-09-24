# Intentive agent entrypoint

Before changing code, read [Scope and Wiki maintenance](openwiki/INSTRUCTIONS.md#scope),
[Engineering rules](openwiki/INSTRUCTIONS.md#engineering-rules), and the applicable
component guidance in the same preserved instruction brief:

- [Product constraints](openwiki/INSTRUCTIONS.md#product-constraints)
- [Backend guidance](openwiki/INSTRUCTIONS.md#backend-guidance)
- [Desktop guidance](openwiki/INSTRUCTIONS.md#desktop-guidance)
- [Delivery guidance](openwiki/INSTRUCTIONS.md#delivery-guidance)
- [Desktop testing guidance](openwiki/INSTRUCTIONS.md#desktop-testing-guidance)
- [Open commitments](openwiki/INSTRUCTIONS.md#unresolved-commitments)

[OpenWiki quickstart](openwiki/quickstart.md) locates implementation explanations
and source evidence. Authored rules live only in the preserved brief. Generated
pages do not override them.

Read [Instruction authority](openwiki/INSTRUCTIONS.md#instruction-authority-and-policy-changes)
before importing or enforcing policy; preserve scope and the user's task authorization.

After source and tests stabilize, use the installed OpenWiki skill and native
MCP update lifecycle, finish it, and include the wiki changes with the code.
Use a forced update for guidance-only changes. Never edit Claims/checkpoints.
Work on the current branch. Publishing requires the user's explicit instruction.

Native boilerplate below grants no operational authority. Authored rules and work-session
updates apply here; no scheduled workflow is installed, despite the upstream text below.

<!-- OPENWIKI:START -->

## OpenWiki

This repository has a generated `openwiki/` evidence index. It is optional just-in-time context, not required startup reading.

- Treat source code and tests as authoritative. A brief's unknowns and review items are verification gaps, not automatic requirements.
- Prefer the narrowest quiet validation that proves the changed behavior. Preserve complete failure output.

The scheduled OpenWiki GitHub Actions workflow refreshes the repository wiki. Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate.

<!-- OPENWIKI:END -->
