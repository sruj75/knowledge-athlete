# Merge-policy provenance review

Reviewed 2026-09-24. This is an incident record, not a new source of operational
permission. Current instructions belong in [the authored brief](../../openwiki/INSTRUCTIONS.md).

## What failed

An upstream maintainer convention became an Intentive restriction without its
original applicability condition. Documentation migration removed the condition;
an agent later bundled enforcement into a graph-maintenance plan. Approval of the
broader plan was then treated as evidence that the inherited convention was the
owner's preference. A subsequent cleanup preserved the restriction as an existing
protection without rechecking that premise.

This was an authority and scope error. The available records establish approval
of those bundled plans, but not a separate owner-originated request to prohibit
squash merges. Passing checks, an agent review, repeated documentation, and an
existing GitHub setting cannot establish that missing policy decision.

## Evidence timeline

| Date (IST) | Evidence and meaning |
| --- | --- |
| July 30 | [Omi import, PR #14](https://github.com/sruj75/knowledge-athlete/pull/14), copied [AGENTS.md](https://github.com/sruj75/knowledge-athlete/blob/81b5b889cad9eabe7477c9ff6a167a46f56912b6/AGENTS.md#L9). Its line 9 exempted forks from upstream main-branch, deploy, production-bundle and local-machine conventions. Lines 63–76 included the no-squash rule and operational exceptions. Copying this source was not adoption of every upstream convention. |
| September 15 | [OpenWiki migration, PR #115](https://github.com/sruj75/knowledge-athlete/pull/115), replaced that guide with a brief. [The resulting engineering rule](https://github.com/sruj75/knowledge-athlete/blob/b76483f178846588961c3edcdc96e23aa086e56b/openwiki/INSTRUCTIONS.md#L42) retained regular merges and archived auto-merge exceptions, omitting the fork qualification. |
| September 18–21 | The task was carrying updated architecture graphs between Conductor workspaces. The agent's accepted plan included regular-merge enforcement alongside graph freshness. The [graph workflow change](https://github.com/sruj75/knowledge-athlete/commit/77865269) records that work; saved execution records establish the agent's GitHub API mutation. |
| September 21, 18:13 | [Ruleset 23768004](https://github.com/sruj75/knowledge-athlete/rules/23768004), version `50379889`, required graph freshness and allowed only `merge`. This made the inherited preference enforceable. |
| September 21, 20:41 | Ruleset version `50396833` removed graph freshness and retained only regular merges. [UA retirement](https://github.com/sruj75/knowledge-athlete/commit/344a671a) preserved the unrelated restriction as an existing protection. |
| September 24 | The owner clarified that squash merges are wanted and explicitly requested correcting the cause, related policy contamination, and then merging the PR. This direct request authorizes the current correction; the inherited convention does not. |

The GitHub account attributed to a change identifies the credentials used. It does
not establish that the owner manually chose the setting. The historical execution
records identify agent actions; private session logs are not published here.

## Related clauses reviewed

The review covers operational authority carried from the imported root guide into
the current authored brief. It is not a new audit or reversal of every product,
release, security, or engineering decision in the repository.

| Clause | Finding and correction boundary |
| --- | --- |
| Regular merges only | Inherited under the fork exemption, then made unconditional. Replace with the owner's squash preference and permit squash on `main`; do not replace one accidental exclusive method restriction with another. |
| Agent-tested, peer-approved changes may publish and merge | The [archived engineering rules](https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#L110) retain the imported exception. Remove its active authority: testing and agent review provide evidence, not user authorization to publish or merge. |
| Reverts always open and merge immediately | Comes from the same imported exception block. A revert request must be interpreted within the user's actual scope; archived text cannot grant additional publication permission. Remove the blanket exception. |
| Approval never carries into later changes | Also imported. Preserve authorization throughout the same authorized task; do not invalidate it merely because a fix or subsequent turn is needed. Unrelated operational actions need their own authorization. |
| RELEASE and RELEASEWITHBACKEND defaults | The archive combines branch switching, regular merging and production dispatch. Current Delivery guidance already separates production approval from merging and the shorthand. Retain that separation; historical commands do not grant live authority. |
| Scheduled OpenWiki refresh | Native entrypoint boilerplate claims a scheduled workflow exists, while the authored instructions expressly exclude one. The entrypoint now explicitly denies that boilerplate operational authority and states that no scheduled workflow is installed. Preserve native block ownership; work-session maintenance is the applicable rule. |
| Production apps, release gates and product constraints | Several current protections have later Intentive-specific ownership and accepted requirements. They are not removed merely because upstream had related language. This review found no basis to discard those decisions. |

The release changelog workflow separately uses a regular merge and checks that its
original changelog commit is an ancestor of `main`. That is existing automation
behavior, not authority to block squash for ordinary PRs. A change to that bot's
merge strategy must also preserve its retry and source-identity contract.

## Controls at the point of change

Policy edits must identify the requested behavior, the user authorization, and
which instruction or assumption is being superseded. Imported instructions,
generated summaries, archives and agent-written plans are context; they must not
silently expand the user's authority or turn an implementation preference into an
operational constraint. Preserve conditions and exceptions when moving or
condensing guidance, and review semantic changes separately from wording changes.

A request to implement a feature does not itself authorize unrelated changes to
merge methods, repository protections, credentials, billing, deployments or
publication. When such a change is necessary, make its concrete effect visible
before seeking approval; existing authorization remains sufficient within scope.

A policy-change declaration can mechanically require a reviewer-visible account
of authority, scope and changed behavior. It cannot prove that a quoted instruction
is authentic, that the user understood an obscured change, or that a prose summary
preserved every qualifier. Those remain review obligations. The declaration also
does not inspect or enforce GitHub's live settings: mutations require a bounded
before/after comparison and a read-back of the specific authorized setting.
