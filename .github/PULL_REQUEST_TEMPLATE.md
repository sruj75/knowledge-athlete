<!-- Keep this short and honest. Reviewers read the Verification section first. -->

## What changed and why

<!-- One or two sentences. Link the issue if there is one. -->

## How it was verified

<!-- The commands you ran and what they showed. Exercising the real user-facing
     path counts as verification; compiling or lint passing does not.
     If something could not be verified, say so explicitly. -->

## Tests

<!-- Bug fix: point to the regression test that would have caught the bug.
     Feature: point to the tests for the core path and main error path.
     No test change: explain why none was needed. -->

## Codebase map

<!-- Choose one after reviewing docs/architecture/intentive-codeflow.mmd. -->

- [ ] Updated the diagram's affected flows and source references in this PR.
- [ ] Reviewed the diagram; this change leaves its flows and references accurate.

## Policy changes

<!-- Required when changing agent instructions, workflow policy or its enforcement.
     Cite the original user decision, not merely an agent-written plan or inherited
     rule. Name the affected behavior, the before/after effect, and the conditions
     or exceptions retained or deliberately changed. For an editorial change,
     explain why behavior and scope remain the same. Delete for unrelated changes.
     This disclosure supports review; it does not authenticate user authorization. -->

Policy-Source:
Policy-Scope:
Policy-Effect:
Policy-Qualifications:

## Failure class (fixes)

<!-- Every `fix:` commit needs this exact, machine-validated declaration.
     Use `scripts/failure-class prepare` or `explain` to choose a class.
     `harden:` commits may cite a class but do not need a declaration. -->

Failure-Class: none

## Failure-class transition narrative (only when needed)

<!-- Required only when declaring `new`, changing a class's canonical prevention
     primitive/owner, or making a registry-only lifecycle transition. A dormant
     transition sets `status: dormant` and an ISO-8601 `dormant_since`; a reopen
     sets `status: open` and removes `dormant_since`. Make that transition in a
     separate PR, never in the instance-fix PR. State the violated contract, the
     canonical guard, and the supporting evidence. Delete this section for an
     ordinary instance fix. -->

## New guards (only when adding a check or ratchet)

<!-- Cite the real merged PR or incident this guard would have caught, then answer
     in one sentence: why is this not a shared primitive instead? Delete this
     section when no check or ratchet is added. -->

## Scoped cleanups (optional)

<!-- Related fixes you made along the way (see AGENTS.md → "Leave It Better
     Than You Found It"). Each should be its own commit and verifiable. -->
