# Pipeline integration

`glance` is intentionally the **display end** of a pipeline — it reads
stdin and shows it in a non-activating panel. The interesting work
(translation, AI, fetching, transforming) happens upstream. This doc
shows ready-to-paste compositions with the rest of the family.

## Family roles (one-liner each)

| Tool | Role | What it provides to `glance` |
|------|------|------|
| [`eventfx`](https://github.com/akira-toriyama/eventfx) | AX event broker | `text_selected` event → `$EVENTFX_SELECTION`, `$EVENTFX_CURSOR_X/Y` |
| [`wand`](https://github.com/akira-toriyama/wand) | gesture + launcher | menu of actions, runs the chosen shell pipeline |
| [`chord`](https://github.com/akira-toriyama/chord) | hotkey daemon | starts the pipeline from a key combo |
| [`perch`](https://github.com/akira-toriyama/perch) | keyboard-driven UI navigator | not directly upstream; coexists |
| [`facet`](https://github.com/akira-toriyama/facet) | workspace + window manager | not directly upstream; coexists |

## Compositions

### A. Translate selection → show near cursor

`eventfx` watches for `text_selected`; pipes the selection to DeepL;
shows the translation right at the cursor without stealing focus.

```sh
# wired up as an eventfx action, or run from wand menu
printf '%s' "$EVENTFX_SELECTION" |
  curl -s -X POST 'https://api-free.deepl.com/v2/translate' \
       -H "Authorization: DeepL-Auth-Key $DEEPL_KEY" \
       --data-urlencode 'text@-' \
       -d 'target_lang=JA' |
  jq -r '.translations[0].text' |
  glance --title 'DeepL' \
         --at "$EVENTFX_CURSOR_X" "$EVENTFX_CURSOR_Y" \
         --auto-close 6
```

The `--at` clamping means the panel stays on-screen even if the cursor
is near the right edge.

### B. AI summary of long stdin

Pipe a long block of text (a doc, a transcript) through Claude, render
the markdown summary.

```sh
echo "$LONG_TEXT" |
  claude-cli "Summarize this in 3 bullets, then list 2 followup questions." |
  glance --markdown --title 'Summary' --width 480
```

Useful inside `wand` as an "AI 要約" menu item — same pipeline, but
the input is `$EVENTFX_SELECTION` or the contents of a focused file.

### C. Definition / dictionary lookup

```sh
word="$EVENTFX_SELECTION"
curl -s "https://api.dictionaryapi.dev/api/v2/entries/en/$word" |
  jq -r '.[0].meanings[] | "**\(.partOfSpeech)** — \(.definitions[0].definition)"' |
  glance --markdown --title "Define: $word" --at "$EVENTFX_CURSOR_X" "$EVENTFX_CURSOR_Y"
```

### D. Quick result toast (HUD mode)

For short results (a time, a calculation, a hash) the HUD mode is
right: borderless, rounded, no titlebar — like a macOS notification.

```sh
# hash the selection
printf '%s' "$EVENTFX_SELECTION" | sha256sum | awk '{print $1}' |
  glance --hud --auto-close 3 --copy

# date / time stamp
date | glance --hud --auto-close 2

# math result
echo "scale=4; $EVENTFX_SELECTION" | bc |
  glance --hud --auto-close 4 --copy
```

`--copy` puts the result on the clipboard so the user can paste it
right after dismissing the toast.

### E. `chord` hotkey: show clipboard with markdown rendering

Bind a hotkey (via `chord`) to display the current clipboard as
rendered markdown — useful when you've copied a markdown fragment
from somewhere and want to read it nicely.

```sh
# chord config snippet
key: "cmd+alt+v"
run: pbpaste | glance --markdown --title 'Clipboard' --width 500
```

### F. `tee` for debugging upstream

If `glance` shows nothing or unexpected text, `tee` the input to a
file so you can inspect what was actually piped:

```sh
some-cmd | tee /tmp/glance-in.txt | glance --markdown --title 'debug'
# then: cat /tmp/glance-in.txt — was the upstream output empty / wrong?
```

`glance` is deliberately quiet on empty stdin (exits 0 with no panel),
so "nothing happened" usually means the pipeline upstream produced
nothing.

## Where `glance` fits

```
┌───────────────────────────────────────────────────────────┐
│ trigger                                                   │
│   eventfx (text_selected) / chord (hotkey) / wand (menu)  │
└──────────────────────────┬────────────────────────────────┘
                           │ stdin
┌──────────────────────────▼────────────────────────────────┐
│ action shell                                              │
│   curl / jq / claude-cli / pbpaste / awk / your script    │
└──────────────────────────┬────────────────────────────────┘
                           │ stdout = stdin
┌──────────────────────────▼────────────────────────────────┐
│ display end                                               │
│   glance --markdown --at X Y --auto-close N --copy        │
│   (non-activating NSPanel, never steals focus)            │
└───────────────────────────────────────────────────────────┘
```

If you find yourself adding HTTP or transformation logic inside
`glance`, it's a signal that the "action shell" stage should grow,
not glance.
