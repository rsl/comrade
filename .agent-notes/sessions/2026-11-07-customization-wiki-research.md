# Handoff — comrade (2026-11-07)

State: the customization-wiki research doc is written, committed, and up
for review as PR #17 on `rsl-customization-wiki` (two commits: `c68bbd4`
handoffs-untracked, `082e65f` the doc; pushed, tracking set). Nothing is
built — research only. Working tree clean except untracked `handoff.md`
(this file, exempt). Agency repo has an uncommitted wording change (see
Open items).

## Built

- **The research doc** (`.agent-notes/research/obsidian-llm-wiki-for-
  comrade-customization.md`, 416 lines, frontmatter `status: active`):
  Karpathy LLM-wiki pattern applied to per-comrade customization. Design
  settled with the developer through the session: per-user **vaulting**
  (not sections — folders in a shared vault leak through every Obsidian
  surface; MemLeak et al. back the hard boundary), household vault in
  (classification rule: a page naming a comrade belongs in that comrade's
  vault), a `sources/` layer (immutable, anonymous, per-URL dedupe,
  retention day one), the 4-bit GLM as intake filing classifier (routing
  only, never promotion; mechanical lint enforces). Non-negotiable kept:
  comrade never reads any vault at turn time — prefs jsonb and the
  prompt file stay the only paths into the model.
- **Registry promoted**: roadmap.md gained a Done bullet (2026-11-07) and
  a closing discussion section "The customization wiki (2026-11-06/07,
  researched — not built)" carrying the settled decisions and the
  build trigger.
- **Agency changes** (separate repo, `~/dev/agency`, all uncommitted):
  - Attribution wording — "developer (or dev) means the human developer;
    end users are 'users' or 'end users'; attribution reads 'the
    developer' or 'developer decision'" (`AGENTS.md` line ~43), plus
    `skills/agent-notes/SKILL.md` ("end-user names" in the sensitivity
    list; "the developer decides what dies" in expire).
  - Handoff skill (`skills/handoff/SKILL.md`) — the multi-branch pause
    design, settled through discussion: parked handoffs
    (`handoff-<branch>.md`) for mid-flight branch pauses with one
    registry breadcrumb; clean-boundary pauses need no park (pointer
    line + graveyard copy); opening act gains step 4 — branch-vs-handoff
    match check and the `handoff-*.md` glob, so nobody has to remember.
    Template's "user's review checklist" → "developer's" rode along.
  - Swept skills/, README, AGENTS.md — no other instances.
  `plans/orchestration.md` deliberately untouched (history keeps its
  provenance).

## Planned, not built

The four-layer wiki (`sources/` + `household/` + per-comrade vaults).
Full design, rejected alternatives, and the smallest first increment
(`sources/` + `household/` only) are in the research doc. Build trigger
documented in roadmap.md — do not start until it fires.

## The user's review checklist

- Read PR #17 — on GitHub app/iPad it renders at
  github.com/rsl/comrade/pull/17 (doc path inside:
  `.agent-notes/research/obsidian-llm-wiki-for-comrade-customization.md`).
  Verify the name scrub took ("the user's verdicts" / "the user noticed",
  zero "rsl" hits — it's tracked territory once merged).
- Review the agency diff in `~/dev/agency` (`git diff`) before committing
  it there — branch rules there are agency's own.

## Open items → registries

- PR #17 merge — the maintainer's; noted in roadmap Done. Merge completes
  the doc's promotion to tracked durable layer.
- Agency commits (wording + handoff skill) — lives in `~/dev/agency`
  working tree only until the developer commits there.
- This branch pauses at a clean boundary: PR open, all state durable, no
  park needed. Resumption act: check PR #17 review, then merge.

## Repro / reference commands

- `agency notes lint` in comrade: exits non-zero on `roadmap.md` missing
  frontmatter — pre-existing, not ours, roadmap is the untracked
  governance file by design.
- Push convention: `push.autoSetupRemote=true` globally, `push.default
  tracking` — bare `git push` after `git co -b rsl-foo` is safe and
  sufficient (developer confirmed; do not add `-u` or touch config).