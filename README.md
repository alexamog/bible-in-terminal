# Bible Verse Lookup Tool

A tiny PowerShell add-on that lets you pull Bible verses (Recovery Version
text) straight from your terminal, read a whole chapter with paging, save
verses you like, and copy verse text straight to your clipboard.

It talks to the free `txo.php` API at `api.lsm.org`. You need your own
`appid` and `token` from [api.lsm.org](https://api.lsm.org) - registration is
free.

## Want a free study Bible?

- Canada: [biblesforcanada.org/order](https://www.biblesforcanada.org/order)
- USA: [biblesforamerica.org/place-order](https://biblesforamerica.org/place-order)

## Commands

| Command | What it does |
|---|---|
| `verse John 3:16` | Prints the verse(s) and **copies the text to your clipboard**. |
| `bible John 3` | Opens a full-chapter reader, one screen-page at a time, sized to your terminal window. |
| `savedverses` | Lists every verse you've saved from the chapter reader. |

### The chapter reader (`bible`)

Run `bible <book> <chapter>` (e.g. `bible Ephesians 4`). You'll see a page of
verses with:

```
[N]ext page   [P]revious page   [S]ave verse   [Q]uit
```

- **N** / **P** move forward/back a whole page.
- **Up / Down arrow keys** scroll one verse at a time, immediately - no need
  to press Enter. This is the one to use when your terminal window is small
  and a full page jump feels too coarse.
- **S** asks for a verse number and saves that *reference* (e.g. "John 3:16")
  to `%USERPROFILE%\.lsm-saved-verses.json`. Run `savedverses` anytime to
  fetch and display the text for everything you've saved.
- **Q** exits back to your normal prompt.
- Typing anything else and pressing Enter jumps straight to that chapter
  (e.g. type `John 4` and hit Enter).

Long verses wrap with a hanging indent so continuation lines line up under
the verse text (not the number), with a blank line between verses. The page
size adapts to your window's actual width and height, so it never overflows
even in a small or narrow pane.

Tip: this reader is much nicer in a **tall, narrow terminal pane** - split
your terminal vertically before running `bible`.

## Install

1. Unzip this folder anywhere.
2. Open PowerShell **in this folder** and run:
   ```powershell
   .\Install.ps1
   ```
   This copies `BibleVerseTool.ps1` next to your PowerShell profile and adds
   one line to your profile that loads it automatically in every new window.
   It also creates a blank credentials file for you if one doesn't exist.
3. Open `%USERPROFILE%\.lsm-verse.json` and replace the placeholders with your
   real credentials from api.lsm.org:
   ```json
   {
     "appid": "YOUR_APPID",
     "token": "YOUR_TOKEN"
   }
   ```
4. Close and reopen PowerShell. Try:
   ```powershell
   verse John 3:16
   ```

### Manual install (if you'd rather not run Install.ps1)

1. Copy `BibleVerseTool.ps1` anywhere you like (e.g. next to your `$PROFILE`).
2. Add this line to your PowerShell profile (find its path by typing
   `$PROFILE`):
   ```powershell
   . "C:\path\to\BibleVerseTool.ps1"
   ```
3. Create `%USERPROFILE%\.lsm-verse.json` with your `appid` and `token` (copy
   `.lsm-verse.example.json` and fill it in).

## Files this tool uses

| File | Purpose |
|---|---|
| `%USERPROFILE%\.lsm-verse.json` | Your API credentials. **Never share this file or commit it anywhere.** |
| `%USERPROFILE%\.lsm-saved-verses.json` | References (not verse text) you've saved with the `[S]ave` option. Plain JSON, safe to open and edit by hand. |

## A note on the API's terms of service

api.lsm.org's terms prohibit storing the Recovery Version text offline, and
require the `copyright` attribution to be shown wherever verses are
displayed. This tool follows both: `savedverses` only ever stores the
*reference* on disk and re-fetches the actual text live from the API each
time you run it, and every command that displays verse text also displays
the attribution line. Clipboard copies (from `verse`) are a transient,
in-memory convenience rather than a stored file.
