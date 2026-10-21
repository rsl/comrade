# Sessions — ephemeral session artifacts

Live session docs live here: session notes, review guides, restart handoffs.
Naming: `YYYY-MM-DD-<slug>.md`.

Lifecycle:

1. **Born here.** A session that needs to hand off state writes its doc in
   this directory, dated.
2. **Open items are promoted, never parked.** Before a session goes idle,
   any open item moves to the repo's single open-items registry (currently
   the README TODOs / GitHub issues once they exist). A doc sitting in here
   with unresolved items in it is a bug.
3. **Consumed means archived — by the reader, not the writer.** A session
   never archives its own handoff: the handoff sits here uncommitted as
   the session boundary, and the NEXT session's opening act is read it →
   commit it (citing the work's shas) → verify its open items live in the
   registry → `git mv` it to `.agent-notes/archive/`. History lives in
   git; the archive keeps it greppable.

The correct steady state at a session boundary: exactly one doc here —
the current handoff, uncommitted.