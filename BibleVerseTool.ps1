# ============================================================
# Bible lookup commands (Recovery Version text, api.lsm.org)
#
#   verse <reference>        e.g.  verse John 3:16
#   verse list               browse your saved references
#   bible <book> <chapter>   e.g.  bible John 3        (paged chapter reader)
#
# Word lookup lives INSIDE the chapter reader only: press ? while reading.
#   savedverses              print every saved verse in one go
#
# Credentials live in:  %USERPROFILE%\.lsm-verse.json
#   { "appid": "YOUR_APPID", "token": "YOUR_TOKEN" }
# Register at https://api.lsm.org to get an appid + token.
#
# Saved references are stored in: %USERPROFILE%\.lsm-saved-verses.txt
#
# "define" uses api.dictionaryapi.dev - free, no key needed. Its data comes
# from Wiktionary under CC BY-SA 3.0, so the source link is always shown.
# ============================================================

function Get-LsmCredential {
    $configPath = Join-Path $HOME ".lsm-verse.json"
    if (-not (Test-Path $configPath)) {
        Write-Host "Credentials file not found: $configPath" -ForegroundColor Yellow
        Write-Host 'Create it containing:  { "appid": "YOUR_APPID", "token": "YOUR_TOKEN" }'
        return $null
    }
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "Could not read $configPath - is it valid JSON?" -ForegroundColor Red
        return $null
    }
    if (-not $config.appid -or -not $config.token -or
        $config.appid -like "YOUR_*" -or $config.token -like "YOUR_*") {
        Write-Host "Please open $configPath and fill in your real appid and token from api.lsm.org" -ForegroundColor Yellow
        return $null
    }
    return $config
}

function Invoke-LsmApi {
    param([Parameter(Mandatory)][string]$Reference)

    $config = Get-LsmCredential
    if (-not $config) { return $null }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $url = "https://api.lsm.org/recver/txo.php?String={0}&Out=json&appid={1}&token={2}" -f
        [uri]::EscapeDataString("'$Reference'"),
        [uri]::EscapeDataString($config.appid),
        [uri]::EscapeDataString($config.token)

    $authBytes  = [Text.Encoding]::ASCII.GetBytes("$($config.appid):$($config.token)")
    $authHeader = @{ Authorization = "Basic " + [Convert]::ToBase64String($authBytes) }

    try {
        # This API replies "Content-Type: application/json" with no charset,
        # so PowerShell 5.1's Invoke-RestMethod assumes Latin-1 and turns the
        # UTF-8 copyright sign into "Â©". Read the raw bytes and decode as
        # UTF-8 ourselves instead.
        $resp = Invoke-WebRequest -Uri $url -Headers $authHeader -TimeoutSec 15 -UseBasicParsing
        $json = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        return ($json | ConvertFrom-Json)
    } catch {
        Write-Host "Request failed: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Invoke-DictApi {
    # api.dictionaryapi.dev - no key, no account. Returns $null when the word
    # is not found (the API answers 404 for that, which is not an error worth
    # shouting about).
    param([Parameter(Mandatory)][string]$Word)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://api.dictionaryapi.dev/api/v2/entries/en/{0}" -f [uri]::EscapeDataString($Word)

    try {
        return Invoke-RestMethod -Uri $url -TimeoutSec 15
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 404) {
            Write-Host "No dictionary entry for '$Word'." -ForegroundColor Yellow
        } else {
            Write-Host "Lookup failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        return $null
    }
}

function Show-Definition {
    # Prints one dictionary entry, wrapped to the window with a hanging indent
    # so long definitions stay readable in a narrow pane.
    param($Entry, [int]$Width)

    if ($Width -le 0) {
        try { $Width = $Host.UI.RawUI.WindowSize.Width } catch { $Width = 80 }
    }

    Write-Host ""
    Write-Host $Entry.word -ForegroundColor Cyan -NoNewline
    if ($Entry.phonetic) { Write-Host "  $($Entry.phonetic)" -ForegroundColor DarkGray } else { Write-Host "" }

    foreach ($meaning in $Entry.meanings) {
        Write-Host ""
        Write-Host "  $($meaning.partOfSpeech)" -ForegroundColor Yellow

        $n = 1
        foreach ($d in @($meaning.definitions | Select-Object -First 3)) {
            $prefix = "    {0}. " -f $n
            $indent = " " * $prefix.Length
            $lines  = @(Get-BibleWrappedLines -Text $d.definition -PrefixLength $prefix.Length -Width $Width)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($i -eq 0) { Write-Host $prefix -NoNewline } else { Write-Host $indent -NoNewline }
                Write-Host $lines[$i]
            }
            if ($d.example) {
                $exLines = @(Get-BibleWrappedLines -Text "e.g. $($d.example)" -PrefixLength ($indent.Length + 2) -Width $Width)
                foreach ($ex in $exLines) {
                    Write-Host ("$indent  " + $ex) -ForegroundColor DarkGray
                }
            }
            $n++
        }

        if ($meaning.synonyms) {
            $syn = (@($meaning.synonyms) | Select-Object -First 6) -join ", "
            foreach ($sl in @(Get-BibleWrappedLines -Text "synonyms: $syn" -PrefixLength 4 -Width $Width)) {
                Write-Host ("    " + $sl) -ForegroundColor DarkGray
            }
        }
    }

    # CC BY-SA 3.0 requires crediting the source.
    if ($Entry.sourceUrls) {
        Write-Host ""
        Write-Host ("Source: {0}  ({1})" -f (@($Entry.sourceUrls)[0], $Entry.license.name)) -ForegroundColor DarkGray
    }
}

function Show-LsmWordLookup {
    # Internal helper for the chapter reader's "?" key. There is deliberately
    # no top-level "def"/"dict" command - word lookup is only offered while
    # reading a chapter.
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Word
    )

    if (-not $Word -or $Word.Count -eq 0) { return }

    $term = ($Word -join " ").Trim()
    $result = Invoke-DictApi -Word $term
    if (-not $result) { return }

    $entry = @($result)[0]
    Show-Definition -Entry $entry -Width 0

    # Deliberately no clipboard copy here - pressing ? mid-chapter should not
    # clobber whatever verse you copied with "verse".
}

function Read-BibleKey {
    # Single keypress, no Enter needed. Returns a small object describing the
    # key. Falls back to Read-Host (first character) if the console has no raw
    # key support (e.g. redirected input, ISE).
    try {
        $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return [PSCustomObject]@{
            Char = $k.Character
            Code = $k.VirtualKeyCode
        }
    } catch {
        $line = Read-Host
        $c = if ($line) { $line[0] } else { [char]13 }
        return [PSCustomObject]@{ Char = $c; Code = 0 }
    }
}

function verse {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Reference
    )

    if (-not $Reference -or $Reference.Count -eq 0) {
        Write-Host "Usage: verse <reference>    e.g.  verse John 3:16" -ForegroundColor Yellow
        Write-Host "       verse list                 browse your saved verses" -ForegroundColor Yellow
        return
    }

    # "verse list" opens the saved-reference browser instead of a lookup.
    if ($Reference.Count -eq 1 -and $Reference[0] -in @("list", "saved", "ls")) {
        verselist
        return
    }

    $result = Invoke-LsmApi -Reference ($Reference -join " ")
    if (-not $result) { return }

    if ($result.message) {
        Write-Host $result.message -ForegroundColor Yellow
    }
    $clipLines = @()
    foreach ($v in $result.verses) {
        Write-Host ""
        Write-Host $v.ref -ForegroundColor Cyan
        Write-BibleText -Text $v.text -Width 0
        # Clipboard keeps the original brackets - plain text, no escape codes.
        $clipLines += "$($v.ref) - $($v.text)"
    }
    if ($result.copyright) {
        Write-Host ""
        Write-Host $result.copyright -ForegroundColor DarkGray
    }

    if ($clipLines.Count -gt 0) {
        $clipLines -join "`r`n`r`n" | Set-Clipboard
        Write-Host ""
        Write-Host "(copied to clipboard)" -ForegroundColor DarkGray
    }
}

# Saved references live in a plain text file, one per line:
#     Rom. 8:26|2026-07-21 08:17:49
# Deliberately NOT JSON: PowerShell 5.1's ConvertTo-Json/ConvertFrom-Json
# round-trip wraps arrays as {"value":[...],"Count":N} and re-nests the store
# on every write. A line-based file has no such quirks and you can open and
# edit it in Notepad.
function Get-LsmStorePath {
    # A function, not a $script: variable - scope resolution for $script: vars
    # differs depending on whether the caller is the script or another
    # function, which silently sent writes to the wrong place.
    return (Join-Path $HOME ".lsm-saved-verses.txt")
}

function Get-LsmSavedRefs {
    # One-time migration from the old .json store, if it is still around.
    $legacy = Join-Path $HOME ".lsm-saved-verses.json"
    if ((Test-Path $legacy) -and -not (Test-Path (Get-LsmStorePath))) {
        $rescued = @()
        # Pull every "ref": "..." out of the old file, however deeply the
        # JSON bug nested it, and keep the first occurrence of each.
        foreach ($m in [regex]::Matches((Get-Content $legacy -Raw), '"ref"\s*:\s*"([^"]+)"')) {
            $r = $m.Groups[1].Value
            if ($rescued -notcontains $r) { $rescued += $r }
        }
        if ($rescued.Count -gt 0) {
            Set-Content -Path (Get-LsmStorePath) -Encoding utf8 -Value (
                $rescued | ForEach-Object { "$_|(migrated)" }
            )
        }
    }

    if (-not (Test-Path (Get-LsmStorePath))) { return @() }

    $out = @()
    foreach ($line in (Get-Content (Get-LsmStorePath) -Encoding utf8)) {
        if (-not $line -or -not $line.Trim()) { continue }
        $parts = $line -split '\|', 2
        $out += [PSCustomObject]@{
            ref     = $parts[0].Trim()
            savedAt = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
        }
    }
    return @($out)
}

function Set-LsmSavedRefs {
    param($Entries)

    $lines = @()
    foreach ($e in @($Entries)) { $lines += "$($e.ref)|$($e.savedAt)" }
    if ($lines.Count -eq 0) {
        Set-Content -Path (Get-LsmStorePath) -Value "" -Encoding utf8
    } else {
        Set-Content -Path (Get-LsmStorePath) -Value $lines -Encoding utf8
    }
}

function Save-LsmVerse {
    # Stores only the reference, never the verse text - api.lsm.org's terms
    # of service prohibit storing any amount of the Recovery Version text for
    # offline use. The text is re-fetched live every time it is displayed.
    param([string]$Reference)

    $saved = @(Get-LsmSavedRefs)
    if ($saved | Where-Object { $_.ref -eq $Reference }) {
        Write-Host "Already saved: $Reference" -ForegroundColor Yellow
        return
    }
    $saved += [PSCustomObject]@{
        ref     = $Reference
        savedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    Set-LsmSavedRefs -Entries $saved
    Write-Host "Saved $Reference" -ForegroundColor Green
}

function Remove-LsmSavedRef {
    param([string]$Reference)

    Set-LsmSavedRefs -Entries @(Get-LsmSavedRefs | Where-Object { $_.ref -ne $Reference })
}

function verselist {
    # Browse saved references. Every action is ONE keypress - no Enter.
    $pageSize = 9   # items labelled 1-9 so a single digit picks one
    $index = 0

    while ($true) {
        $saved = @(Get-LsmSavedRefs)
        if ($saved.Count -eq 0) {
            Write-Host "No saved verses yet. Open a chapter with 'bible John 3' and press S." -ForegroundColor Yellow
            return
        }
        if ($index -ge $saved.Count) { $index = [Math]::Max(0, $saved.Count - $pageSize) }

        Clear-Host
        Write-Host "== Saved verses ==" -ForegroundColor Cyan
        Write-Host ""

        $pageEnd = [Math]::Min($index + $pageSize, $saved.Count) - 1
        for ($i = $index; $i -le $pageEnd; $i++) {
            $label = $i - $index + 1
            Write-Host ("  {0}) " -f $label) -ForegroundColor Yellow -NoNewline
            Write-Host $saved[$i].ref -NoNewline
            Write-Host ("   saved {0}" -f $saved[$i].savedAt) -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("{0}-{1} of {2}" -f ($index + 1), ($pageEnd + 1), $saved.Count) -ForegroundColor DarkGray
        Write-Host ""

        $hasNext = ($pageEnd + 1) -lt $saved.Count
        $hasPrev = $index -gt 0
        $opts = @("press 1-9 to read")
        if ($hasNext) { $opts += "[N]ext" }
        if ($hasPrev) { $opts += "[P]rev" }
        $opts += "[D]elete"
        $opts += "[Q]uit"
        Write-Host ($opts -join "   ") -ForegroundColor Green

        $key = Read-BibleKey
        $ch  = "$($key.Char)".ToUpper()

        if ($key.Code -eq 40 -and $hasNext) { $index += $pageSize; continue }   # Down arrow
        if ($key.Code -eq 38 -and $hasPrev) { $index -= $pageSize; continue }   # Up arrow

        switch ($ch) {
            "N" { if ($hasNext) { $index += $pageSize } }
            "P" { if ($hasPrev) { $index = [Math]::Max(0, $index - $pageSize) } }
            "Q" { return }
            "D" {
                Write-Host ""
                Write-Host "Press number to DELETE (any other key cancels):" -ForegroundColor Red
                $dk = Read-BibleKey
                if ("$($dk.Char)" -match '^[1-9]$') {
                    $pick = $index + [int]"$($dk.Char)" - 1
                    if ($pick -le $pageEnd) {
                        Remove-LsmSavedRef -Reference $saved[$pick].ref
                        Write-Host "Deleted $($saved[$pick].ref)" -ForegroundColor Green
                        Start-Sleep -Milliseconds 600
                    }
                }
            }
            default {
                if ($ch -match '^[1-9]$') {
                    $pick = $index + [int]$ch - 1
                    if ($pick -le $pageEnd) {
                        Clear-Host
                        verse $saved[$pick].ref
                        Write-Host ""
                        Write-Host "Press any key to go back to the list..." -ForegroundColor Green
                        Read-BibleKey | Out-Null
                    }
                }
            }
        }
    }
}

function savedverses {
    $storePath = Join-Path $HOME ".lsm-saved-verses.json"
    if (-not (Test-Path $storePath)) {
        Write-Host "No saved verses yet." -ForegroundColor Yellow
        return
    }
    $saved = @(Get-Content $storePath -Raw | ConvertFrom-Json)
    if ($saved.Count -eq 0) {
        Write-Host "No saved verses yet." -ForegroundColor Yellow
        return
    }

    $copyright = $null
    foreach ($v in $saved) {
        $result = Invoke-LsmApi -Reference $v.ref
        Write-Host ""
        Write-Host $v.ref -ForegroundColor Cyan
        if ($result -and $result.verses -and $result.verses.Count -gt 0) {
            foreach ($verseObj in $result.verses) {
                Write-BibleText -Text $verseObj.text -Width 0
            }
            if ($result.copyright) { $copyright = $result.copyright }
        } else {
            Write-Host "(could not fetch text right now)" -ForegroundColor Red
        }
        Write-Host "  saved $($v.savedAt)" -ForegroundColor DarkGray
    }
    if ($copyright) {
        Write-Host ""
        Write-Host $copyright -ForegroundColor DarkGray
    }
}

function Read-BibleInput {
    # Reads keys one at a time so Up/Down arrow can act immediately (no Enter
    # needed), while any typed text is still collected until Enter is pressed.
    # Falls back to plain Read-Host if the console doesn't support raw key reads.
    try {
        $buffer = ""
        while ($true) {
            $keyInfo = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            switch ($keyInfo.VirtualKeyCode) {
                38 { if (-not $buffer) { return @{ Action = "ScrollUp" } } }   # Up arrow
                40 { if (-not $buffer) { return @{ Action = "ScrollDown" } } } # Down arrow
                34 { if (-not $buffer) { return @{ Action = "Submit"; Text = "N" } } } # PageDown
                33 { if (-not $buffer) { return @{ Action = "Submit"; Text = "P" } } } # PageUp
                32 {
                    # Space pages forward only when nothing typed yet;
                    # otherwise it is a real space inside "John 4".
                    if (-not $buffer) { return @{ Action = "Submit"; Text = "N" } }
                    $buffer += " "
                    Write-Host " " -NoNewline
                }
                9  { if (-not $buffer) { return @{ Action = "Submit"; Text = "S" } } } # Tab
                27 { return @{ Action = "Submit"; Text = "Q" } }                       # Esc
                13 { Write-Host ""; return @{ Action = "Submit"; Text = $buffer } } # Enter
                8  {
                    if ($buffer.Length -gt 0) {
                        $buffer = $buffer.Substring(0, $buffer.Length - 1)
                        Write-Host "`b `b" -NoNewline
                    } else {
                        # Nothing typed: Backspace means "go back to where I
                        # was reading before I jumped".
                        return @{ Action = "Back" }
                    }
                }
                default {
                    $ch = $keyInfo.Character
                    if (-not $ch -or [int]$ch -lt 32 -or [int]$ch -eq 127) { break }

                    # Nothing typed yet: N/P/S/Q fire instantly, no Enter.
                    # Book names also start with N/P/S (Numbers, Psalm,
                    # Samuel, Song of Songs), so "/" opens typing mode for
                    # those. Any other letter just starts typing normally,
                    # so "John 4" still works with no prefix.
                    if (-not $buffer) {
                        if ("$ch" -eq "/") {
                            Write-Host "reference: " -NoNewline -ForegroundColor Green
                            $buffer = " "   # non-empty marker: typing mode is on
                            break
                        }
                        if ("$ch" -eq "?") {
                            return @{ Action = "Define" }
                        }
                        if ("$ch" -match '^[NnPpSsQq]$') {
                            Write-Host ""
                            return @{ Action = "Submit"; Text = "$ch" }
                        }
                    }
                    $buffer += $ch
                    Write-Host $ch -NoNewline
                }
            }
        }
    } catch {
        return @{ Action = "Submit"; Text = (Read-Host) }
    }
}

function Get-BibleWrappedLines {
    # Word-wraps $Text to fit ($Width - $PrefixLength) characters per line.
    # Returns an array of lines (always at least one, even for empty text).
    param([string]$Text, [int]$PrefixLength, [int]$Width)

    $maxLineWidth = [Math]::Max(10, $Width - $PrefixLength - 1)
    $words = $Text -split '\s+'
    $lines = @()
    $current = ""
    foreach ($w in $words) {
        if ($current.Length -eq 0) {
            $current = $w
        } elseif (($current.Length + 1 + $w.Length) -le $maxLineWidth) {
            $current += " $w"
        } else {
            $lines += $current
            $current = $w
        }
    }
    if ($current) { $lines += $current }
    if ($lines.Count -eq 0) { $lines = @("") }
    return $lines
}

function Split-BibleEmphasis {
    # The Recovery Version brackets words supplied by the translators - e.g.
    # "[He] [said,]" - which print in italics on paper. Split the text into
    # words, each flagged as emphasised or not, so the brackets themselves
    # never have to be shown.
    param([string]$Text)

    $tokens = @()
    foreach ($m in [regex]::Matches($Text, '\[[^\]]*\]|[^\[\]]+')) {
        $seg  = $m.Value
        $emph = $seg.StartsWith('[')
        $body = if ($emph) { $seg.Trim('[', ']') } else { $seg }
        foreach ($w in ($body -split '\s+')) {
            if ($w -ne '') {
                $tokens += [PSCustomObject]@{ Text = $w; Emph = $emph }
            }
        }
    }
    return @($tokens)
}

function Write-BibleText {
    # Word-wraps on VISIBLE width (styling is applied at print time, never
    # baked into the string - ANSI codes would otherwise be counted as
    # characters and wreck the wrapping).
    param(
        [string]$Text,
        [string]$Prefix       = "",
        [string]$PrefixColor  = "Yellow",
        [int]   $Width
    )

    if ($Width -le 0) {
        try { $Width = $Host.UI.RawUI.WindowSize.Width } catch { $Width = 80 }
    }

    $esc      = [char]27
    $italicOn = "$esc[3m"
    $italicOff= "$esc[23m"

    $indent = " " * $Prefix.Length
    $max    = [Math]::Max(10, $Width - $Prefix.Length - 1)
    $tokens = Split-BibleEmphasis -Text $Text

    $line   = @()   # tokens on the current line
    $len    = 0
    $first  = $true

    $flush = {
        if ($first) {
            if ($Prefix) { Write-Host $Prefix -ForegroundColor $PrefixColor -NoNewline }
        } else {
            Write-Host $indent -NoNewline
        }
        # Build the line as one string, opening/closing italics only when the
        # emphasis actually changes, so "[a period of]" is a single run.
        $sb   = ""
        $open = $false
        for ($j = 0; $j -lt $line.Count; $j++) {
            # Close italics before the separating space, open them after it,
            # so the styling hugs the words instead of the gap.
            if (-not $line[$j].Emph -and $open) { $sb += $italicOff; $open = $false }
            if ($j -gt 0) { $sb += " " }
            if ($line[$j].Emph -and -not $open) { $sb += $italicOn; $open = $true }
            $sb += $line[$j].Text
        }
        if ($open) { $sb += $italicOff }   # never leave italics on at line end
        Write-Host $sb
    }

    foreach ($t in $tokens) {
        $add = if ($len -eq 0) { $t.Text.Length } else { $t.Text.Length + 1 }
        if ($len -gt 0 -and ($len + $add) -gt $max) {
            & $flush
            $first = $false
            $line  = @()
            $len   = 0
            $add   = $t.Text.Length
        }
        $line += $t
        $len  += $add
    }
    if ($line.Count -gt 0) { & $flush }
    elseif ($first -and $Prefix) { Write-Host $Prefix -ForegroundColor $PrefixColor }
}

function Write-BibleVerseLine {
    # Prints a verse with its number, wrapping long text with a hanging
    # indent so continuation lines line up under the verse text, not the number.
    param([string]$Number, [string]$Text, [int]$Width)

    Write-BibleText -Text $Text -Prefix ("{0,3}  " -f $Number) -PrefixColor Yellow -Width $Width
}

function bible {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if (-not $Args -or $Args.Count -lt 2) {
        Write-Host "Usage: bible <book> <chapter>    e.g.  bible John 3" -ForegroundColor Yellow
        return
    }

    $chapterRef = $Args -join " "
    $result = Invoke-LsmApi -Reference $chapterRef
    if (-not $result) { return }

    if (-not $result.verses -or $result.verses.Count -eq 0) {
        if ($result.message) { Write-Host $result.message -ForegroundColor Yellow }
        else { Write-Host "No verses returned for '$chapterRef'." -ForegroundColor Yellow }
        return
    }

    $verses = @($result.verses)

    $index = 0
    $pageHistory = New-Object System.Collections.Generic.List[int]

    # Where you were reading before each jump, so Backspace can return you to
    # the exact chapter AND scroll position - not just the top of it.
    $readingHistory = New-Object System.Collections.Generic.List[object]

    while ($true) {
        Clear-Host
        Write-Host "== $chapterRef ==" -ForegroundColor Cyan
        Write-Host ""

        try {
            $termWidth  = $Host.UI.RawUI.WindowSize.Width
            $termHeight = $Host.UI.RawUI.WindowSize.Height
        } catch {
            $termWidth  = 80
            $termHeight = 25
        }
        $availableLines = [Math]::Max(3, $termHeight - 8)

        # Figure out how many verses fit, counting wrapped lines + a spacer
        # line per verse, so a page never overflows a small/narrow window.
        $pageEnd   = $index
        $linesUsed = 0
        for ($i = $index; $i -lt $verses.Count; $i++) {
            $need = (Get-BibleWrappedLines -Text $verses[$i].text -PrefixLength 5 -Width $termWidth).Count + 1
            if (($linesUsed + $need) -gt $availableLines -and $i -gt $index) { break }
            $linesUsed += $need
            $pageEnd = $i
        }

        for ($i = $index; $i -le $pageEnd; $i++) {
            $num = if ($verses[$i].ref -match ':(\d+)') { $matches[1] } else { $i + 1 }
            Write-BibleVerseLine -Number $num -Text $verses[$i].text -Width $termWidth
            Write-Host ""
        }

        Write-Host ("Verses {0}-{1} of {2}" -f ($index + 1), ($pageEnd + 1), $verses.Count) -ForegroundColor DarkGray
        if ($result.copyright) { Write-Host $result.copyright -ForegroundColor DarkGray }
        Write-Host ""

        $hasNext = ($pageEnd + 1) -lt $verses.Count
        $hasPrev = $index -gt 0
        $options = @()
        if ($hasNext) { $options += "[N]ext page" }
        if ($hasPrev) { $options += "[P]revious page" }
        $options += "[S]ave verse"
        $options += "[Q]uit"
        Write-Host ($options -join "   ") -ForegroundColor Green
        # Full key list lives in README.md, not on screen - it ate two lines
        # of reading space on every page.

        Write-Host ">" -NoNewline -ForegroundColor Green
        Write-Host " " -NoNewline
        $input = Read-BibleInput

        switch ($input.Action) {
            "ScrollDown" {
                if ($index -lt ($verses.Count - 1)) { $index++ }
            }
            "ScrollUp" {
                if ($index -gt 0) { $index-- }
            }
            "Back" {
                if ($readingHistory.Count -gt 0) {
                    $prev = $readingHistory[$readingHistory.Count - 1]
                    $readingHistory.RemoveAt($readingHistory.Count - 1)
                    $chapterRef = $prev.Ref
                    $result     = $prev.Result
                    $verses     = @($prev.Result.verses)
                    $index      = $prev.Index
                    $pageHistory.Clear()
                    foreach ($h in @($prev.PageHistory)) { $pageHistory.Add($h) }
                }
            }
            "Define" {
                Write-Host ""
                $word = Read-Host "define"
                if ($word -and $word.Trim()) {
                    Clear-Host
                    Show-LsmWordLookup $word.Trim()
                    Write-Host ""
                    Write-Host "Press any key to go back to the chapter..." -ForegroundColor Green
                    Read-BibleKey | Out-Null
                }
            }
            "Submit" {
                $trimmed = $input.Text.Trim()
                switch ($trimmed.ToUpper()) {
                    "N" {
                        if ($hasNext) {
                            $pageHistory.Add($index)
                            $index = $pageEnd + 1
                        }
                    }
                    "P" {
                        if ($pageHistory.Count -gt 0) {
                            $index = $pageHistory[$pageHistory.Count - 1]
                            $pageHistory.RemoveAt($pageHistory.Count - 1)
                        } elseif ($hasPrev) {
                            $index = 0
                        }
                    }
                    "S" {
                        # One keypress picks a verse: label the verses on this
                        # page a, b, c... so no typing (and no multi-digit
                        # verse numbers) is needed.
                        $letters = [char[]]"abcdefghijklmnopqrstuvwxyz"
                        Write-Host ""
                        for ($i = $index; $i -le $pageEnd; $i++) {
                            $li = $i - $index
                            if ($li -ge $letters.Count) { break }
                            Write-Host ("  {0}) {1}" -f $letters[$li], $verses[$i].ref) -ForegroundColor Yellow
                        }
                        Write-Host "Press a letter to save (any other key cancels):" -ForegroundColor Green
                        $pk = "$((Read-BibleKey).Char)".ToLower()
                        $li = [Array]::IndexOf($letters, [char]$pk)
                        if ($li -ge 0 -and ($index + $li) -le $pageEnd) {
                            Save-LsmVerse -Reference $verses[$index + $li].ref
                            Start-Sleep -Milliseconds 700
                        }
                    }
                    "Q" {
                        return
                    }
                    "" {
                        # empty input, just redraw
                    }
                    default {
                        # anything else is treated as a new "Book Chapter" reference to jump to
                        $newResult = Invoke-LsmApi -Reference $trimmed
                        if ($newResult -and $newResult.verses -and $newResult.verses.Count -gt 0) {
                            # Remember where we were so Backspace can return.
                            $readingHistory.Add([PSCustomObject]@{
                                Ref         = $chapterRef
                                Result      = $result
                                Index       = $index
                                PageHistory = @($pageHistory.ToArray())
                            })
                            $result     = $newResult
                            $verses     = @($newResult.verses)
                            $chapterRef = $trimmed
                            $index      = 0
                            $pageHistory.Clear()
                        } else {
                            Write-Host "Could not find '$trimmed' - try a format like 'John 4'." -ForegroundColor Red
                            Read-Host "Press Enter to continue" | Out-Null
                        }
                    }
                }
            }
        }
    }
}

