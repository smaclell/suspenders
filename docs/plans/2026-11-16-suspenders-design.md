# Suspenders — design

A gentle habit nudger: a calm new tab that reminds you who you want to be, light
friction on YouTube in the evening, and a soft push to sign off at night.

## Goals

- Every new tab is a small nudge towards the identity you want: a value-aligned
  quote or a passage from your own notes (Obsidian).
- 8:30 PM – 10:00 PM: YouTube still works, but with friction.
- After 10:00 PM: YouTube is blocked; whole-laptop use is gently discouraged.
- A real, effortful override exists for genuine needs, and every reason is logged
  so patterns become visible.

## Research notes

- **Momentum-style new tabs** work because they're calm: full-bleed background,
  big clock, greeting, one piece of content.
- **Friction beats blocking for the grey zone.** Tools like *one sec* show that a
  short pause before an app opens cuts usage significantly. *Unhook*-style removal
  of recommendations reduces rabbit-holing without removing utility.
- **Overrides** work best when they cost effort *and* time (write a reason, then
  wait), and when reasons are reviewed later.
- **Platform limits:** a Chrome extension cannot read a local folder without
  repeated permission prompts and cannot see time spent outside Chrome. A small
  native helper fixes both.

## Architecture

```
┌────────────────────── Chrome extension (MV3) ──────────────────────┐
│ newtab.html   clock · greeting · quote / note passage card          │
│ youtube.js    gate · hide recs · grayscale · block redirect         │
│ blocked.html  reason (≥20 words) → 5 min wait → 15 min unlock       │
│ options.html  times, quotes, reasons log                            │
│ background.js schedule phase, overrides, reason log                 │
└───────────────┬────────────────────────────────────────────────────┘
                │ http://127.0.0.1:47615 (loopback only, optional)
┌───────────────┴──────────── Suspenders Helper (macOS menu bar) ─────┐
│ VaultIndex    reads tagged notes (#nudge #anki #quote) → passages    │
│ HTTP server   GET /snippet  GET /status  POST /reasons               │
│ Activity      idle time via CGEventSource → minutes active tonight   │
│ Sign-off      notifications · amber tint · wind-down card · menu bar │
└──────────────────────────────────────────────────────────────────────┘
```

The extension works fully without the helper (built-in quotes, local reason log).

### Schedule phases (configurable)

| Phase      | Default window   | YouTube                               | Laptop            |
|------------|------------------|---------------------------------------|-------------------|
| `day`      | 05:00 – 20:30    | normal                                | —                 |
| `evening`  | 20:30 – 22:00    | 10 s gate, recs hidden, grayscale fade| —                 |
| `night`    | 22:00 – 05:00    | blocked (override available)          | nudges, tint, card|

### Note selection

A note is eligible if its frontmatter `tags` or inline `#tags` include one of the
configured tags (default `nudge`, `anki`, `quote`).

- `quote` notes → each blockquote / list item becomes a quote.
- other notes → split by heading, then grouped paragraphs (~200–700 chars).

### Override flow

1. Write a reason (minimum 20 words).
2. Wait 5 minutes (countdown persists across reloads).
3. YouTube unlocked for 15 minutes (calm mode still on).
4. Reason saved to extension storage and, if the helper runs, appended to a
   markdown log (optionally inside the vault).

### Privacy

- No personal data in the repository. All personal config (vault path, tags,
  times) lives in `~/Library/Application Support/Suspenders/config.json` and
  `chrome.storage`.
- The helper binds to `127.0.0.1` only and answers CORS only for
  `chrome-extension://` origins.

## Deferred ideas

- Email-to-self as an unlock requirement (needs a mail service to verify).
- Hard block with no override.
- Watch-session cap ("wrap up" after 20 min).
- Readwise / Notion sources.
- Background photos (needs an image API key).
