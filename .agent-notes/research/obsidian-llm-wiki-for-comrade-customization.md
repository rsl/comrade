---
title: Obsidian + LLM wiki for keeping up with per-comrade customization
status: active
summary: Headline design for per-comrade customization memory — one vault per comrade plus a shared household vault and a shared raw-sources layer, with leak analysis, pros/cons, gotchas, and the rejected alternatives.
---

# Obsidian + LLM wiki for keeping up with per-comrade customization

Overnight research, 2026-11-06; reworked same weekend after the user's
verdicts:
per-user **vaulting** (not per-user sections) is the decided shape, the
shared household vault is in, and the raw-sources layer is answered below.
Amended 2026-11-07 (with the developer): background ingest of sources —
the runtime enqueues fetched pages, a serialized job queue writes
`sources/`; see "Background ingest of sources."
Research doc — nothing here is built.

## Headline design

Four layers under one root (`comrade-wikis/` is a placeholder name):

```
comrade-wikis/
  sources/      # raw layer — immutable, anonymous, per-URL dedupe, retention
  household/    # shared synthesis — common space, no comrade-attributed facts
  <comrade>/    # one vault per comrade — the hard boundary
```

- **Per-comrade vaults are the isolation mechanism.** The boundary is the
  filesystem, not a convention sessions are asked to remember. A section
  or folder inside a shared vault was the original framing; the research
  rejects it (see rejected alternatives).
- **The household vault is common space** for facts true of the house,
  not of one comrade. In comrade's model its consumption path is the
  system prompt file (`config/comrade_prompt.md` custom override) — the
  household analogue of `prefs_message`: per-comrade knowledge rides
  prefs jsonb, household knowledge rides the prompt. One injection point,
  config not rows, compiled at write time.
- **The sources directory is the raw layer** Karpathy's pattern calls for:
  immutable input the wiki is compiled from. Not really an Obsidian
  vault — nobody graphs raw sources; they're found by path and cited by
  relative path.
- **Comrade never reads any of it at turn time.** The only paths into the
  model stay the existing two: `prefs_message` (per comrade) and the
  prompt file (household). Reviewed material is *promoted* into those;
  the wiki is the workshop, prefs/prompt are the shipped config.
- **The commune gets no vault** — mirroring "the commune always gets the
  factory voice." (Household knowledge reaches the commune anyway via the
  global prompt file; that is consistent with the commune being the
  shared space, but it is a choice to keep conscious.)
- **A small filing classifier routes intake.** The local 4-bit GLM decides
  which vault a fact belongs in; sessions write the text. See "The filing
  classifier" below.
- **Maintainers are opencode sessions** on the operator's machine, under
  a per-vault schema doc (the Karpathy `AGENTS.md` layer), plus one
  background-ingest path: comrade's runtime enqueues fetched pages to a
  serialized job queue that files them into `sources/` — a handoff, not
  a write. The runtime never opens a vault, names a path, or makes a
  filing decision; vault synthesis and promotion stay session-side.

## What comrade has today (the constraints)

Facts from the repo that any design must respect:

- Identity is the `comrades` table behind `Comrade::Enlistee` — authless
  token, unique permanent names, `prefs:jsonb` and `calibration:jsonb`
  (`db/migrate/20261024120000_create_comrades.rb`). The commune is
  `conversations.comrade_id: nil`.
- Prefs reach the model through one injection point forever:
  `Comrade::Reply#prefs_message` layers them as a second system message
  after the base prompt. Values are directive lines the reader authored;
  keys are addresses. The comment is explicit: "prefs are config, never a
  row." The commune always gets the factory voice.
- Calibration is telemetry **only the code reads** — the model never sees
  it. Prefs and calibration are separate blobs precisely "so the border is
  a column boundary" (`app/models/comrade/enlistee.rb`).
- Schema laws (`schema` skill): jsonb over extra tables, no User model,
  and **no database in the correctness path for retrieval decisions**.
- Ethos (README): local-first, "your questions are nobody's training data
  if they never leave your machine."

## The LLM wiki pattern (Karpathy's gist, April 2026)

Three layers: **raw sources** (immutable inputs), **the wiki**
(LLM-generated, LLM-maintained markdown — entity/concept pages, summaries,
cross-references, contradiction flags), **the schema** (an `AGENTS.md`
governing structure and maintenance workflows).

Three operations: **ingest** (read source, update 10–15 pages, log it),
**query** (answer from the wiki; file good answers back in), **lint**
(health-check: contradictions, stale claims, orphans, missing pages).

Two special files: `index.md` (catalog — the retrieval mechanism at
moderate scale, ~hundreds of pages, no vector RAG needed) and `log.md`
(append-only, greppable `## [date] op | subject` entries).

Why it works: the wiki is a persistent, compounding artifact. RAG
re-derives synthesis on every query and the good answers die in chat
history; the wiki keeps them. The maintenance burden that killed every
human wiki is near-zero for an LLM.

2026 ecosystem status (verified):

- **Open Knowledge Format (OKF)** — Google Cloud formalized the pattern
  into a portable spec (v0.1 June 2026, v0.2 since): directory of markdown
  files, YAML frontmatter, one required `type` field, conventional
  headings. Optional; adopt if interop ever matters.
- **Search tooling** — `qmd` (tobi/qmd): local hybrid BM25/vector search
  over markdown, CLI + MCP. Needed only past index.md scale.
- **MCP access to Obsidian** — two families: filesystem MCP pointed at a
  folder (covers ~90% of use; works with Obsidian closed; folder
  allowlist is the auth) and REST-API MCPs (need Obsidian running; atomic
  edits, more tools). Community servers: Vault Cortex (33 tools, protected
  paths, read-only mode, `.obsidian` locked off), obsidian-mcp-server-
  enhanced (multi-vault), Nexus, and others catalogued on Glama.
- **Community failure-mode lore** (gist comments + write-ups):
  near-duplicate pages are the default failure ("extend, don't create");
  append-instead-of-rewrite rots topic pages; periodic "dream" passes
  merge drifted pages; ~72% of ingest tokens went to filing *decisions*
  (a small typed classifier beat the LLM at that); every implementation
  that survived added mechanical (non-model) lint checks; most wikis only
  logged ingests, not queries — "the wiki had it and the model ignored
  it" becomes unprovable unless queries are logged too.

## Leak analysis — what "no leak" has to mean here

Three distinct surfaces, each with its own answer. The multi-tenant
memory literature is directly applicable (MemLeak paper, arXiv 2610.04195;
Hindsight and supermemory write-ups):

1. **Model surface (comrade → comrade).** Comrade B's turn must never see
   comrade A's material. Today this is enforced structurally:
   `prefs_message` reads only `@conversation.comrade&.prefs` — the row is
   the boundary. The design preserves this: **no vault is ever read at
   turn time**, and promotion into prefs is per-comrade by construction.
   Per-turn file reads would move the boundary from a column to a path
   convention — a soft partition, exactly the pattern MemLeak shows
   leaking ("inter-user semantic resonance": pooled storage with metadata
   filtering pulls neighbors' data in on semantic similarity alone).
2. **Maintainer surface (opencode sessions).** Sessions must never get a
   path above their comrade's directory: a filesystem MCP allowlisted to
   that vault root, or plain file tools plus separate working dirs. This
   is MemLeak's "partitioned deployment" — the only arrangement that
   stayed clean in every study read for this doc. Hindsight's framing is
   the rule: draw the seal where the system enforces it, not where you
   must remember to enforce it.
3. **Viewer surface (Obsidian UX).** Inside one vault, folders do not
   confine anything: global search crosses folders, the graph view merges
   everyone into one picture, backlinks surface other comrades' notes,
   unscoped Dataview queries read everything, Obsidian Sync syncs the
   whole vault, and "recently opened" leaks filenames. The Felo write-up
   states it plainly: "The vault is a single container… True isolation
   requires multiple vaults." Per-user vaulting makes this surface moot
   — each vault is opened alone, so there is nothing to leak into.

## The household vault: classification and promotion

The household vault holds facts true of the house, not of one comrade:
shared schedule, devices, standing style preferences ("dinner-table
level, two languages"), shared projects, the model server's lanes.

**The classification rule (write-path gate):** if a page names or
characterizes a specific comrade, it belongs in that comrade's vault —
never the household vault. "The household prefers plain answers" is
household; "the user noticed comrade X keeps asking about medical stuff" is
per-comrade and calibration-adjacent at that. A fact from one comrade's
private conversations enters the household vault only if it has been
generalized past attribution **and** confirmed by the humans — a
promotion gate with two keys (session proposes, humans confirm).

**Consumption:** household pages promote into the custom prompt file —
global by nature, so the commune receives household context too (fine,
but a choice). Per-comrade pages promote into that comrade's `prefs`
jsonb. Calibration-adjacent material stays in the wiki and never gets
promoted, preserving the "model never sees calibration" border by
construction.

**Human visibility asymmetry:** per-comrade vaults are, in spirit, that
comrade's space plus the operator's. The household vault is common space
— every human who opens it reads all of it. Anything one member wouldn't
want the others to read doesn't belong there, whatever its technical
classification.

## The sources layer: yes, its own directory — with rules

Karpathy's pattern already has this layer; the question was whether it
deserves separation as a fourth directory. Answer: yes, because the
layers have opposite needs — sources are big, noisy, third-party content
that should be immutable; wikis are small, curated, derived.

Why separate:

- Keeps wiki vaults lean. Large files and attachments are Obsidian's real
  performance killer, not note count (~1000 markdown files start in
  seconds).
- Makes "sessions never edit raw" structural — the schema doc says
  read-only, and nothing in the wiki vaults can be confused for source.
- Retention: raw material can age out (or be pruned) without touching
  compiled knowledge — the wiki holds the synthesis, so the bulk raw
  doesn't have to live forever. Clean deletion story for third-party
  content, too: it lives nowhere near anything that might be synced,
  published, or shown.
- Dedupe as a feature: when two comrades' research pulls the same page,
  one source page per URL, and both wikis cite the same source — a shared
  fetch cache by convention.

Rules that keep it safe:

- **Provenance is anonymous.** A source page records where the *page*
  came from (URL, fetch date, clip method), never which comrade surfaced
  it. "Comrade X searched this" is per-comrade or calibration-adjacent;
  folding it into a shared source page is the exact misfiling the
  household rule forbids.
- **Citations are relative paths, not wikilinks** (cross-vault links
  don't exist in Obsidian), with a mechanical broken-citation lint —
  MindBase's `broken citation` check is the model: a script verifies the
  cited source path still exists.
- **It's a clipping library, not surveillance.** Two ingest paths, one
  anonymity rule. Sessions clip sources during wiki work (non-fetch
  material: local notes, conversation-derived facts). Comrade's runtime
  enqueues fetched pages to the background ingest job (see "Background
  ingest of sources" below). What neither path may record is *who*:
  provenance names the page, never the comrade. The calibration-adjacent
  danger is attribution, not ingestion — "comrade X searched this" is
  the forbidden sentence, not "this page exists in the library."
- **Growth is unbounded, so a retention policy comes day one** (e.g.
  expire un-cited sources after N months; lint lists citations so "is
  this source still cited?" is scriptable).

## Background ingest of sources

The runtime path into `sources/` (added 2026-11-07, with rsl): after a
turn's page fetches, comrade enqueues the URL and fetched text to a
dedicated GoodJob queue — `wiki_ingest`, concurrency 1. Enqueueing is a
handoff, not a wiki write: the runtime opens no vault, names no path,
makes no filing decision. The job does the writing, anonymously.

- **Why a job:** ingest is LLM calls plus file writes — seconds to
  minutes. Inline would stall the turn; async holds nothing back.
- **Why serialized:** one job at a time closes job-vs-job races on the
  same vaults and documents. Job-vs-session writes (a maintainer session
  rewriting a page mid-ingest) stay last-write-wins, covered by the
  git-per-vault discipline and the sessions-edit-humans-browse habit.
- **Idempotent under retry:** GoodJob retries. Dedupe by URL makes a
  retried source ingest a no-op; log entries carry an idempotency key
  (URL + date) so a retry can't double-append `log.md`.
- **Retention ships with the job, not deferred.** A robot curator grows
  the layer unbounded; the expire-un-cited-sources lint lands in the
  same increment.
- **Scope:** `sources/` only. The job never writes a vault, and
  promotion stays behind the human gate.

## The filing classifier

The intake router is the local 4-bit GLM (the same endpoint comrade
rides), applied to the crow-hq finding from the gist comments: ~72% of
ingest tokens went to *filing decisions* — which folder, same subject as
an existing page, merge or not — not writing. Handing those decisions to
a small local model while the big one writes the text raised routing
accuracy from 62% to 89%, with per-document token cost flat as the wiki
grew. The decision space here is friendlier than crow-hq's: few labels,
crisp rules.

**It decides** (all intake filing, session-side tooling — the maintainer
session shells out to the local endpoint during ingest):

- **Which vault** a new fact belongs in (`sources/` / `household/` /
  comrade-A / comrade-B). The household rule is nearly mechanical already
  ("names or characterizes a specific comrade → that comrade's vault") —
  the best possible shape for a small classifier, with the vault manifest
  in the prompt.
- **Extend or create** — the near-duplicate check, the pattern's default
  failure mode.
- **Source dedupe** — "have we clipped this URL before?" is nearly
  deterministic.

**It never decides:**

- **Promotion.** Nothing reaches `prefs` or the prompt file without the
  human confirmation gate, at any confidence. The classifier files within
  the wiki; it never ships config.
- **A confident misroute.** Defense in depth: the classifier proposes,
  the mechanical lint enforces. The dangerous direction — comrade-
  attributed content landing in `household/` or `sources/` — is caught
  by the grep tripwire (household and sources pages are scanned for
  comrade names after every write, whatever the classifier said).
  Misroutes in the harmless direction (a household fact filed into one
  comrade's vault) are misfiling, not leaks — that comrade could see the
  material anyway.

**Confidence routing:** the classifier outputs label + confidence;
anything below threshold goes to a human decision. The expected wobble
is boundary cases — "the household prefers plain answers *because*
comrade X kept asking" is one sentence from being per-comrade — and the
chain handles it: cheap model proposes, cheap script verifies, human
confirms anything that ships.

**Scope:** operator-side only. Comrade's runtime never touches the
classifier, same as it never touches the wiki.

## Pros of the whole idea (in comrade's context)

- **Compounding memory for the household.** Today customization is two
  jsonb keys and a manual Party Line. The wiki gives sessions a place
  where per-comrade context accumulates instead of living in session
  transcripts that decay.
- **The maintenance cost argument is real.** Sessions don't get bored;
  ingest touching the index, log, and pages is one pass.
- **Human-legible and human-auditable.** Markdown in Obsidian: the
  operator reads exactly what the system believes about each comrade;
  git per vault makes every evolution reviewable and revertible —
  including "what did we change about this comrade last month."
- **Fits the ethos.** Local files, no third-party memory service, no
  enclosure. The hosted alternatives (Mem0, supermemory, Hindsight) were
  rejected on politics grounds alone.
- **Clean deletion.** A comrade leaving is `rm -rf` of one directory —
  the derived personal data goes with it, not just the DB row.
- **OKF gives an exit ramp.** If comrade ever ships or shares profiles,
  OKF-formatted markdown is portable without lock-in.

## Cons and gotchas

Cons first, honestly:

- **Scale mismatch.** Comrade is pre-alpha, single household, a handful
  of comrades. The pattern earns its keep around dozens of sources and
  hundreds of pages; per-comrade customization may top out at a dozen
  lines, at which point prefs jsonb alone is the smallest thing that
  works and the wiki is ceremony. The honest con: this may be a solution
  shopping for a problem until customization volume grows.
- **New maintenance discipline.** The wikis need lint passes, duplicate
  policing, and log upkeep — or they become the stale thing the
  literature warns about.
- **Three systems to keep in sync.** Wiki pages vs shipped prefs vs
  household prompt lines can drift. Needs the rule: prefs/prompt are
  authoritative once promoted; wiki pages mark promoted lines.
- **Per-vaulting ergonomics cost.** No cross-vault wikilinks (Obsidian
  can't link across vaults — citations go by relative path); several
  Obsidian windows/configs if the human browses; per-vault MCP configs
  or disciplined session working dirs.

Gotchas, concrete and sourced:

1. **Folders don't isolate** — search, graph, backlinks, Dataview, and
   sync all cross folders inside one vault. The reason per-user
   *sections* were rejected and vaults chosen.
2. **Wikilinks are vault-global with autocomplete** — inside any single
   vault, accidental cross-topic links are one keystroke away.
3. **Agent + Obsidian concurrent edits = last-write-wins.** A session
   rewriting a page while Obsidian holds it open loses one side's edit
   silently. Habit: sessions edit, humans browse.
4. **Sync-tool conflict copies.** iCloud/OneDrive/Dropbox over a vault
   produce `conflicted copy` churn, especially `.obsidian/workspace.json`,
   which every open Obsidian instance rewrites. If any vault syncs at
   all, exclude `.obsidian` or use Obsidian Sync/git.
5. **Plugin-dependent wikis break quietly.** Dataview dashboards don't
   render on mobile or Publish; heavy DataviewJS lags mid-size vaults.
   Prefer plain markdown + index.md; scope any Dataview query with
   `FROM "folder"` and a `LIMIT`.
6. **Near-duplicates are the default failure.** The schema must mandate
   "check index.md + search before creating a page," and lint needs a
   duplicate check.
7. **Rewrite, don't append, on topic pages** — appending turns a summary
   into an unnavigable changelog. Contradictions get a section, not a
   trail of edits.
8. **Mechanical checks beat model checks.** Broken links, orphans,
   duplicate names, "page not touched since its source changed,"
   broken source citations are all scriptable; don't rely on the model
   to notice them.
9. **Log all three operations**, not just ingests — else "the wiki had
   it and the model ignored it" is unprovable.
10. **The wiki holds inferences about a person** — derived personal data
    beyond anything comrade's DB stores. The per-vault boundary, the
    promotion gate (nothing model-inferred becomes prefs without explicit
    confirmation), and git history as audit trail are the answers.
11. **Secret-shaped text accretes.** Notes quoting conversations can pick
    up tokens/keys. Lint for secret-shaped strings (cortex's approach).
12. **Context budget at injection.** Prefs ride every turn against
    `max_tokens: 8192` with the transcript; prompt lines ride every turn
    including the commune's. Promotion discipline (few, load-bearing
    lines) is a functional requirement, not style.
13. **Misclassification is the leak.** The failure mode to lint for:
    comrade-attributed facts in the household vault, reader-attributed
    facts in the sources layer. A lint pass can grep household pages for
    comrade names as a tripwire.
14. **Performance is fine at this scale** — attachments, not notes, are
    the killer; the sources layer is the only place volume lives, and it
    is deliberately outside the wiki vaults.
15. **Two writers, one layer.** Background ingest jobs and maintainer
    sessions both write the wiki tree. The serialized queue closes
    job-vs-job; job-vs-session is last-write-wins like agent+Obsidian
    (gotcha 3) — the same habit covers it.

## Rejected alternatives

- **Shared vault with per-comrade folders** (the original "new section"
  framing). Rejected: soft partition — every Obsidian surface crosses
  folders, and the multi-tenant literature shows metadata-style
  separation leaking under semantic similarity. The requirement is
  no-leak, not discouraged-leak.
- **Comrade reads vaults at turn time.** Rejected: moves the isolation
  boundary from the column to a path convention, violates "no database
  in the correctness path," and puts retrieval judgment in the runtime.
- **Hosted memory services (Mem0, supermemory, Hindsight, cognee).**
  Rejected: politics and local-first — per-user isolation as a paid
  third-party service contradicts the README.
- **Vector RAG over transcripts.** Rejected: re-derives per query (the
  pattern's whole point is to stop doing that) and adds a database to the
  correctness path.
- **One vault per comrade *and* duplicating household facts into each.**
  Rejected: three copies, three staleness clocks, drift guaranteed.

## Recommendation

1. Build nothing yet — with one amendment (2026-11-07): the sources
   layer's trigger is **content preservation**, independent of
   customization volume. When fetched-page research starts dying in
   transcript decay, or the same URL gets re-fetched across sessions,
   the `sources/` layer plus the background ingest job justify
   themselves on preservation alone. The customization triggers stand
   as written: sessions re-deriving the same per-comrade context from
   transcripts more than occasionally, prefs lines fighting the
   8192-token budget, or the prompt file accumulating household lines
   that need maintenance.
2. When triggered, start with the shape above: `sources/` + `household/`
   + one vault per comrade, sessions as maintainers under per-vault
   schema docs, promotion gates as specified.
3. Steal the survivor lore up front: extend-don't-create,
   rewrite-don't-append, log all operations, mechanical lint (including
   the misclassification tripwire), promotion gate, `.obsidian` excluded
   from any sync.
4. The smallest first increment: `sources/` + `household/` only, no
   per-comrade vaults — household knowledge in the prompt file gets a
   maintenance surface before any per-comrade knowledge does, and the
   background source-ingest job rides with it. Per-comrade vaults
   arrive with the first comrade whose context outgrows prefs lines.

## Search log

Read: Karpathy's gist (full text + gist-comment implementations: MindBase,
Link 5.0, cortex, podcast-wiki, llmwiki/OKF v0.2, crow-hq classifier
finding); Felo "Obsidian vault vs workspace" (vault-is-one-container
finding); Glama/MCP-server comparisons + contextbolt (filesystem vs REST
MCP); Obsidian forum threads on sharing/sync conflicts; MemLeak
(arXiv 2610.04195), Hindsight, supermemory, CockroachDB, cognee on
multi-tenant memory isolation; Neo4j and MindStudio on wiki scaling
failure modes; ken.moriwaki's LLM Wiki 1/3 (mechanical lint rules);
OKF spec + GitBook/Google Cloud posts; Obsidian performance and Dataview
threads.

Not checked: whether any Obsidian MCP server enforces per-vault tool
scoping well enough to prefer over plain file tools; Kamal-deployed
comrade reading vault files over the network (ruled out by design —
never a turn-time read anyway); retention tooling for the sources layer
(none chosen; a lint-plus-expire script is the assumed shape).