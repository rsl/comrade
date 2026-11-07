# Sessions — ephemeral session artifacts

Live session docs live here: session notes, review guides, restart handoffs.
Naming: `YYYY-MM-DD-<slug>.md`.

These docs are **untracked working state** — never committed. The durable
record lives in `roadmap.md` (decisions, riders) and `docs/` (architecture);
a handoff only points there. A handoff never needed a commit, and committing
one puts a bookkeeping commit on whatever branch the close-out runs on —
main included, where commits are forbidden.

Lifecycle:

1. **Born here, untracked.** A session that needs to hand off state writes
   its doc in this directory, dated.
2. **Open items are promoted, never parked.** Before a session goes idle,
   any open item moves to the repo's registry (roadmap.md). A doc sitting
   in here with unresolved items in it is a bug.
3. **Archived when superseded, not when read.** The successor session's
   opening act: read the live handoff, verify its open items live in the
   registry. At that session's close-out it writes its own handoff first,
   then moves the old one to `.agent-notes/archive/`, annotating anything
   the session proved wrong. The move is a local `mv` — no commit, no
   ceremony. A session never archives its own handoff, and never archives
   its predecessor before the new handoff exists.

Expiry is `agency notes expire`'s job — the archive grows until pruned.

The correct steady state: exactly one doc here — the live handoff.