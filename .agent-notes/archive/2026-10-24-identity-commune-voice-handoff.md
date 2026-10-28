# Session handoff — 2026-10-24, identity, the gate, and the drawer

> Archived 2026-10-26, already superseded by the 2026-10-25 handoff at
> write time; its archive rode the close-out commit. Nothing in it
> proved wrong that the later handoffs don't correct.

**State: Sat 2026-10-24, evening, mid-review. Branch `rsl-onboarding-enlistment`
holds 11 unpushed commits through `573c7b0`. Everything since — the enlist
gate, the sidebar rework, the copy sweep, the phone drawer — is UNCOMMITTED
in the tree, by design: rsl's new commit rule (codified in AGENTS.md, itself
uncommitted) requires a per-batch go-ahead, and the batched commit ask is
the next act. 20 specs green, rubocop/reek/herb clean, Tailwind rebuilt.
rsl reviewed on iPad (good) and iPhone (enlisted as Bam-Bam — claim-by-name
worked); the one bug he found (unviewably dark drawer) is fixed and awaits
his reload. This doc replaces the earlier identity handoff written mid-
session — same session, rewritten in place; one doc per session.**

## Built since the last handoff (all uncommitted)

- **The enlist gate owns the main window.** Every tokenless browser on
  the new-chat surface gets the full-window ask — preamble paragraphs
  (locality, residency, perimeter, then commune-or-handle), name field,
  "or Stay in the commune". NO memory of dismissal: the 400-day seen
  cookie and the punt cookie both died. "Stay in the commune" is a
  client-side reveal (card hides; composer, greeting, sidebar appear);
  a reload asks again. A handle is the only permanent exit. Conversation
  views never gate — being in one IS the choice. Copy decisions:
  "handle" not "name"; the preamble's handwave ("not really private,
  but basically, yeh?") is load-bearing — the claim path means anyone
  in the house can be anyone, and the copy admits it.
- **Gate centering.** The card centers on the window via transcript
  `pb-26` when gated: bottom padding = reserved title row (4rem) + top
  padding (2.5rem), all rem-based so it holds at every font scale. The
  composer strip goes p-0 when gated. No negative margins — padding is
  the knob.
- **Sidebar rework.** Fixed 240px, px-pinned paddings; order is wordmark
  → Conversations → Archives (hidden when empty) → bottom cluster
  (identity chip, Change the party line?, font sizer) pinned by
  `mt-auto`. The chip is verbless — just the name (rsl rejected "asking
  as", then "here as" for space) — truncating, aria-label carries the
  full name. The party line lives INSIDE the identity section as a
  sentence-link toggle ("Change the party line?", always underlined,
  details/summary expands the field). The structural hairline went
  neutral (`border-ground-bright`); red in the sidebar stays semantic.
- **Calibration offer moved into the conversation.** It rides the latest
  answer's footer line (next to Break it down) — where the clicks that
  earned it happened — rendered in BOTH renders byte-identically via the
  `keep-simple` data value on the stream-reader controller. Yes / No
  thanks post and delete `/calibration` as before. The offer specs moved
  to a conversation page surface.
- **Copy sweep.** Standard capitalization: Title Case buttons and nav
  links (Enlist, Save, Step out, Archive / Unarchive / Destroy),
  capitalized links and labels (Break it down, Double check, Simpler by
  default?, Stay in the commune, Change the party line?), (Untitled),
  From model knowledge, capitalized placeholders. The canned turns in
  the stream reader are untouched — they're the user's typed voice, and
  BREAK_DOWN_TURN must stay in lockstep.
- **Phone drawer.** Below 640px the sidebar becomes a fixed overlay
  sliding from the LEFT (matching the ☰ top-left), toggled by a ☰ button
  (hidden when gated), dismissed by outside tap, conversation tap, or ☰
  again. `sidebar_drawer_controller.js`; backdrop `bg-black/60
  sm:hidden`. Desktop never sees any of it (`max-sm:` variants only —
  Tailwind rebuilt after class changes).

## The dark-drawer bug (the one open diagnostic, resolved)

rsl's iPhone showed the drawer "unviewably dark". Diagnosis chain: NOT
iOS stacking quirks and NOT the palette — `tmp/sample_png.rb` (a pure-
Ruby PNG pixel sampler written for this, no image gems on the box)
measured the drawer surface at exactly `#230a0a` under 60% black. The
cause: TWO backdrops — my iOS-fix edit added an in-shell backdrop but
left the original body-level one in place; the body-level one paints
above the whole shell (DOM order, both fixed), veiling everything.
Fixed by deleting the body-level leftover; post-fix measurements show
the drawer at its true rgb(35,10,10) with the veil only over the
content behind it. Lesson: measure, don't eyeball; and
`elementFromPoint` + computed z-index via Selenium executescript is the
fast path to stacking truth.

## Open items → registry

All promoted to `roadmap.md` (Open questions): the batched commit ask
(the whole UI arc — suggested split: gate+centering, sidebar+party line,
calibration offer, copy sweep, drawer — but rsl decides), rsl's phone
re-verify after reload, the squash of d31f35c + 4ec5205, push/PR after
verdicts and commits. Proposed but undecided: a permanent preamble home
("What is comrade?" link in the identity section); hiding the ☰ while
the drawer is open (it currently floats over the drawer wordmark).
Carried untouched: dead-code riders (marker_index, sawCitations), stray
iOS caret, phase-5 specs, remaining copy polish (tweaking stage).
Disposable dev-db rows: sidebar-probe comrade, probe conversations.

## Next session's opening act

Read this, verify the registry, collect rsl's verdicts on the drawer
fix and the rest of the review. Then the batched commit ask — nothing
commits before it (the new rule). Push + PR after commits. Archiving
this doc happens when its successor is written — not before, not on
read.