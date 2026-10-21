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
3. **Archived when superseded, not when read.** A handoff is half
   record, half plan — reading it doesn't consume it. The next
   session's opening act is only: read it, verify its open items live
   in the registry. Nothing moves, nothing commits. The archive move
   belongs to close-out: when the session that consumed it writes its
   own handoff, it writes the new one FIRST, then moves the old one to
   `.agent-notes/archive/`, annotates anything the session proved
   wrong, and commits it there citing the work's shas. A session never
   archives its own handoff, and never archives its predecessor before
   the new handoff exists — a crash in between leaves the old handoff
   here as the live plan, which is correct. History lives in git; the
   archive keeps it greppable.

The correct steady state: exactly one doc here — the live handoff. It
leaves only when its successor is written.