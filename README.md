# Bible Verse Lookup Tool

A tiny PowerShell add-on that lets you pull Bible verses (Recovery Version
text) straight from your terminal, read a whole chapter with paging, save
verses you like, and copy verse text straight to your clipboard.

It talks to the free `txo.php` API at `api.lsm.org`. You need your own
`appid` and `token` from [api.lsm.org](https://api.lsm.org) - registration is
free.

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
- **S** asks for a verse number and saves that verse (reference + text) to
  `%USERPROFILE%\.lsm-saved-verses.json`. View them anytime with
  `savedverses`.
- **Q** exits back to your normal prompt.
- Typing anything else and pressing Enter jumps straight to that chapter
  (e.g. type `John 4` and hit Enter).

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
| `%USERPROFILE%\.lsm-saved-verses.json` | Verses you've saved with the `[S]ave` option. Plain JSON, safe to open and edit by hand. |

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Credentials file not found" | Run `Install.ps1` again, or create `.lsm-verse.json` by hand (see above). |
| "Please open ... and fill in your real appid and token" | The credentials file still has the placeholder values - edit it. |
| "Request failed: ..." | Usually no internet connection, or the appid/token is wrong/expired. |
| `verse` / `bible` "is not recognized" | Your profile didn't load - reopen PowerShell, or check `$PROFILE` actually dot-sources `BibleVerseTool.ps1`. |

## Want to understand how it works, or build something like it yourself?

See **`Lab - Building the Bible Verse Lookup Tool.pdf`** in this folder. It's
a beginner-friendly, hands-on lab that walks through building this exact tool
from scratch - functions, calling a REST API, reading JSON, a save-to-file
pattern, and a simple paging loop - no prior PowerShell experience assumed.
