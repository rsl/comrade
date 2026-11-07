# Sessions — session notes and the handoff graveyard

Live handoffs do NOT live here anymore: each in-flight branch's state is
`.agent-notes/handoff-<branch>.md` (gitignored, one per branch — see the
handoff skill; `handoff.md` is a legacy leftover, `mv`'d to the branch
file on first touch). This directory holds dead handoffs plus session
notes and review guides, named `YYYY-MM-DD-<slug>.md` by birth date.

Lifecycle:

1. **Born here.** Session notes and review guides are written in this
   directory, dated. Live handoffs are born at `.agent-notes/handoff-
   <branch>.md` instead.
2. **Open items are promoted, never parked.** Before a session goes
   idle, any open item moves to the repo's single open-items registry
   (currently `.agent-notes/roadmap.md`; GitHub issues once they
   exist). A doc sitting in here with unresolved items in it is a bug.
3. **Archived when the branch dies, not when read.** A handoff is half
   record, half plan — reading it doesn't consume it. The move to this
   graveyard belongs to the session that witnesses the branch merge or
   die: write nothing first, just move the file, annotate anything the
   work proved wrong, and cite the work's shas. A session never
   archives a live branch's handoff — its own or another's — and a
   handoff whose branch still exists stays put, even a stale-looking
   one; the branch is the truth. History lives in git; the graveyard
   keeps it greppable.

The correct steady state: one `handoff-<branch>.md` per in-flight
branch in `.agent-notes/`, and nothing in here that any branch still
needs.