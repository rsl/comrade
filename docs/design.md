# Design

The UI's physical laws — the contracts every view, helper, and Stimulus
controller keeps. When code and this file disagree, fix one or the other
in the same commit.

## The fixed shell

`application.html.erb` is a fixed `inset` shell: the document never
scrolls. The transcript panel scrolls internally; the composer is a
shell footer. All scrolling — the stream reader's autoscroll pinning,
jump-to-latest, every scroll target — aims at the transcript panel,
never `window`.

Why: every document-scroll state on iOS Safari becomes a bug class of
its own — dead scroll, pan-on-focus, scroll carry across the
landing-to-show Turbo.visit. The shell keeps scrolling where the app
owns it.

## Sizing from the visual viewport

No `100vh`-family unit sizes a full-height surface in this app. Each of
`vh`, `svh`, and `dvh` lies in a different URL-bar and keyboard state,
and iOS Safari ships no `interactive-widget` (expected in Safari 27.1),
so the meta viewport hint is inert where it matters most. Worse, iOS
scrolls the window itself on focus even when nothing is scrollable, and
never reverts it.

The shell therefore sizes itself from `visualViewport.height` — see
`app/javascript/controllers/visual_viewport_boot.js` — and pins
`window.scrollY` to 0 around focus.

The measured evidence (iPad Safari 26, via a `?vvdebug` readout that
never shipped):

- Keyboard closed: `vv.height == innerHeight == shell == 875`.
- Keyboard open, pre-fix: `scrollY=69` — iOS scrolled the window on
  focus and left it there, dragging fixed content out from under the
  chrome. `vv.offsetTop=0`: never a visual-viewport pan.
- Keyboard open, post-fix: `vv.height=806`, shell `806px`, `scrollY=0`
  held by the pin.
- URL-bar states move the "full" height too (875 expanded, 932
  collapsed) — which is exactly why every viewport unit lied, each in a
  different state.
- The keyboard's floating accessory bar appears a beat before the
  viewport resize fires: the shell lags one frame and catches up. A
  self-healing transient, not a bug — nothing page-side can detect the
  bar directly.

The debugging lesson generalizes: viewport state is won with numbers,
not pixels — one readout capture beat a dozen screenshot round-trips.

## The twin-render contract

A turn exists twice: the client render built by
`stream_reader_controller.js` while streaming, and the server render in
`_message.html.erb` that replaces it when the post-first-reply
Turbo.visit swaps the page. The two must stay pixel-identical — same
elements, same classes, same text — or one side of the swap shows
something the other doesn't.

Anything state-bearing must be born identically in both renders. It has
bit twice: the title spacer (2026-10-23), the empty tool-notes wrapper
(2026-10-24). Drift never fails loudly; it shows up after the visit, on
one side only.

## Styling: `c-` component classes

When the server render and its client twin build the same element, their
class lists cannot share a constant across languages — and hand-kept
copies drift silently. Shared styling for twin elements lives in
`app/assets/tailwind/application.css` under `@layer components`, as a
house-defined class prefixed `c-` (e.g. `c-turn-log`, `c-shell`). The
rationale comment rides the definition; state classes like `hidden` and
toggle marks ride the call site, never the definition. One-off styling
stays inline; within one language, a repeated string stays a constant.