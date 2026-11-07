---
title: Image attachments for conversations
status: built 2026-11-07
summary: Settled design for comrades attaching images to a turn for the model to parse — disk + jsonb refs, keep-or-shrink staging, drag/paste/picker entrances, read_image tool as the model's full-res escape hatch.
---

# Image attachments for conversations

Designed 2026-11-07 with rsl across a planning session. Branch:
`rsl-image-attachments` (cut from `main` at 5f8d21e, nothing built).
Input mix rsl named: mostly screenshots and memes/images saved from the
internet — that fact shaped the staging and the escape hatch.

Vision is settled: GLM is multimodal (confirmed in use since the
2026-10-31 provenance research; rsl waived the oMLX wire-shape probe
2026-11-07 — the one-probe check of image content parts through the lane
rides free with the first real image turn).

## Settled decisions

1. **Storage: content-hash files on disk + jsonb refs.** Bytes live at
   `storage/uploads/<content-hash>.<ext>` (the ImageProxy pattern —
   hash-keyed, no table, no Active Storage). `messages.images` is jsonb:
   an array of refs `{ key, ext, content_type, width, height, source_url
   (when a browser drop carried one), full_key (when a downsampled copy
   differs) }`. Rejected: Active Storage (machinery the repo uses
   nowhere), base64-in-jsonb (bloats rows, backups, every transcript
   load).
2. **`message.content` stays a plain string.** The text of the turn is
   text; images live only in the jsonb. This keeps `retry_case`'s
   content comparison, `archive_line`, title derivation, and the
   calibration signal working untouched.
3. **Wire: all images, every turn.** `to_transcript` builds the OpenAI
   multimodal content array only for user rows carrying images —
   `content: [{type: 'text'}, {type: 'image_url', image_url: {url:
   'data:image/jpeg;base64,…'}}]` — base64 read from disk at request
   time. Assistant and tool rows unchanged. Rejected: recent-turns-only
   with older images degrading to a text note — the model loses sight of
   images still under discussion; cost is bounded by staging.
4. **Entrances: drag-anywhere + drop + paste + attach button.** Drop
   listeners on the whole transcript shell (anywhere on the conversation,
   not just the composer); paste (⌘V of a screenshot) rides the same
   staging path — `clipboardData.files` and `dataTransfer.files` share a
   shape. The button triggers a hidden `<input type="file"
   accept="image/*" multiple>` — on iOS that IS the Photos picker and
   the only mobile flow (no programmatic Photos access exists; no
   showOpenFilePicker on iOS Safari; iPhone has no cross-app drag.
   iPadOS drag from Photos into Safari works through the same drop path
   for free).
5. **Staging: keep-or-shrink, format-preserving.** An image at or under
   ~1280px max side stays byte-for-byte (PNG screenshots keep their text
   crisp — no JPEG re-encode). Over the cap: canvas downsample to
   ~1280px, JPEG ~0.8. The staged chip shows the resolved size. rsl's
   direction: downsample by default, but the model gets an escape hatch
   when text is illegible — decision 6.
6. **`read_image` tool: the model's full-res escape hatch.** The wire
   request carries downsampled images; when the model finds text
   illegible it calls `read_image(ref)` and a tool round delivers that
   image's full-resolution copy. Full-res bytes ride the wire only on
   demand. Portability caveat to settle at build with the live endpoint:
   image content inside tool-role messages is not guaranteed across
   OpenAI-compatible endpoints — fallback shape is the full-res frame
   delivered as an image-bearing message right after the tool call.
7. **Uploads carry both sizes when they differ.** Staging is client-side
   (canvas — the stack has no server-side image tooling and this avoids
   adding one): the client sends the original data URL plus the
   downsampled one when it shrank. Server stores both (each under its
   own hash); the wire uses the downsampled copy, `read_image` the
   original. Under-cap images are one file, one ref.
8. **Provenance for free.** A browser image drag carries the source URL
   (`text/uri-list`) alongside the bytes; v1 still uses the bytes but
   records the URL in the ref — "where did this meme come from" has a
   hook.
9. **Serving: same-origin by unguessable hash key**, the `/img/` proxy
   pattern. Uploaded bytes never ride a foreign host; thumbnails and
   lightbox views fetch from comrade itself.
10. **Image-only sends are legal.** Empty text with images attached
    passes the composer gate (`!content && !images`); `start!` needs a
    fallback title for a blank first message ("Image" / count).
11. **Scope: images only in v1.** The 2026-10-23 open item said "and/or
    text extraction per file type" — text files are out of scope here,
    a later increment. Non-image drops and non-decodable images (HEIC
    outside Safari's canvas, files over a 10 MB cap mirroring
    ImageProxy's) get a visible inline rejection.

## Build order

1. Migration: `add_column :messages, :images, :jsonb`.
2. Server: `Comrade::Reply` accepts `images:` beside `content:`,
   decodes data URLs to hash-keyed files, persists refs on the user row;
   `to_transcript` multimodal arrays; `read_image` in the tool registry,
   offered when the turn carries attachments. Retries work unchanged —
   refs live on the row.
3. Serving route/controller for uploaded bytes by hash key.
4. Client staging in `stream_reader_controller`: staged-image chips
   (thumbnail, resolved size, remove) above the composer, drop on the
   whole shell, paste listener, hidden input behind the button, canvas
   staging, `images: [dataURL,…]` added to the existing JSON POST — no
   multipart, no form changes.
5. Rendering twins: thumbnails in user turns; `_message.html.erb` and
   the stream reader's `turnHtml`/`appendExchange` stay byte-identical
   per the house rule.
6. Image-only first turns: `start!` fallback title.
7. Lint clean (rubocop, reek, herb, brakeman) before done; specs land
   after the shape settles, per the repo's testing law.

## Constraints on the build

- The fixed inset-shell: the drop overlay must not introduce document
  scroll — all scrolling stays in the transcript panel.
- HEIC from Photos decodes in Safari's canvas but not desktop Chrome;
  v1 accepts what the staging browser can decode and says so otherwise.
- Never run `bin/rails tailwindcss:build` by hand — the watcher is the
  only build mechanism in-session.
- Scratch files and screenshots in `tmp/`.