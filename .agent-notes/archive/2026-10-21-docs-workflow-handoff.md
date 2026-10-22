# Session handoff — 2026-10-21, docs, PR workflow, provenance scrub

> Archived 2026-10-21 by the consuming session. Correction to the record:
> Dependabot alerts were verified NOT flowing — both alerts and automated
> security updates are now enabled (via API, this session).

**State: everything merged and pushed. `main` at `43678d3` (merge of PR #6),
working tree clean except this handoff. CI fully green — lint, scan_js,
scan_ruby, test, system-test. Nothing unmerged, nothing pending on GitHub.**
Next session starts Phase 1 (schema & models) per the roadmap, on a fresh
branch, via PR.

Note for an iPad session: the repo lives on the Mac Studio at
`~/dev/comrade`; every durable fact is either on disk here, in the pushed
repo, or in `.agent-notes/roadmap.md` (untracked — it exists only on the
Studio's disk).

## Built

- **`docs/architecture.md`** — the public name inventory: services,
  schema, ENV vars, files that matter, one-line rationale where the reason
  isn't obvious. The README keeps the politics; this keeps the
  architecture. It is now the public home of the settled decisions, and
  the file's own header states the law: when code and doc disagree, fix
  the doc in the same commit.

- **Agent workflow made public** (PR #5, merge `13be110`). AGENTS.md, the
  skills, and the session-docs lifecycle are committed. Session docs are
  public from birth: nothing unsigned, no local paths, no private-work
  provenance. `roadmap.md` alone stays untracked — its governance voice
  ("do not relitigate") and local details don't survive strangers, and its
  public value is fully carried by the architecture doc. `.gitignore`
  enforces this.

- **PR workflow is now the law, server-enforced.** A branch ruleset
  requires changes to `main` through PRs; direct pushes are rejected. After
  rsl hit the solo-maintainer deadlock (GitHub never lets a PR author
  approve their own PR), the ruleset was set to **0 required approvals,
  merge method only**. Working agreement states the practice: one branch +
  one PR per working session, `rsl-` prefix, granular commits, few pushes,
  merge after rsl has seen it. Squash is off the table repo-side — the
  granular history is the value; the merge commit is the session boundary.

- **Lint provenance scrubbed.** The custom rubocop cop came from FA's
  private `unifractured` gem — written at FA, so work-for-hire. The file
  was reauthored as a project-local variant of RuboCop's *stock*
  `Layout::MultilineMethodArgumentLineBreaks` (behavior identical: calls
  with lambda/block arguments are exempt). The old commit naming the
  private gem was rewritten out of history via rebase (new lint commit is
  `e3f24cc`) and force-pushed. Remaining "Fractured Atlas" mentions in
  `.rubocop.yml` (upstream header + vendored-copy attribution) point at
  FA's *public* linters repo, which invites use in its README — left
  deliberately. The decision record lives in the roadmap's Linting row.

- **Dependabot off until Phase 5** (its yml removed in PR #5's branch,
  four PRs closed unmerged). Weekly bot PRs against a review-gated main
  was noise for a pre-alpha app. Phase 5 re-enables it; security alerts
  are *expected* to still flow via GitHub's alert settings — **unverified,
  see review checklist**.

- **CI system-test fixed** (PR #6, merge `43678d3`). The scaffold CI ran
  `test:system` but Rails 8.1 creates `test/system` only alongside the
  first system test, so the job died on `LoadError` — green job now via an
  empty `test/system/.keep`, which is the state Phase 3 inherits anyway.

## Planned, not built

- **Phase 1 — schema & models** is next per the roadmap: `conversations`
  and `messages` migrations, models with validations, transcript
  serialization. No auth, no user references. Branch name suggestion:
  `rsl-schema-models`.
- `docs/searxng.md` lands with Phase 4 (the README and architecture doc
  both already reference it).
- Phase 5 carries: real tests, reek/herb CI steps, Dependabot re-enable,
  fresh-clone README verification.

## rsl's review checklist

- Skim `docs/architecture.md` rendered on GitHub — it's the first
  contributor-facing doc; the voice should pass the repo-voice bar.
- Settings → Rules → Rulesets → "Main": confirm it reads the way you want
  (0 approvals, merge only, no bypass actors).
- Settings → Code security: confirm Dependabot alerts (and ideally
  security updates) are enabled — I asserted alerts flow without checking.

## Open items → registries

All promoted to `.agent-notes/roadmap.md` this close-out: new settled
rows (Docs, Git workflow, Dependencies, amended Linting provenance), the
Done list updated through both PRs, Phase 5 carries the Dependabot
re-enable and the security-alert verification. Phase 1 remains the next
build phase. No open item lives only in this handoff.

## Next session's opening act

1. Read this handoff, verify the open items are in the roadmap, archive
   this file (`git mv` to `.agent-notes/archive/`), commit citing
   `13be110` and `43678d3`.
2. Branch `rsl-schema-models` off up-to-date `main`, and begin Phase 1
   per the roadmap — plan before editing, approval gate applies.