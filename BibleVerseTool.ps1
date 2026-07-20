# ============================================================
# Bible lookup commands (Recovery Version text, api.lsm.org)
#
#   verse <reference>        e.g.  verse John 3:16
#   bible <book> <chapter>   e.g.  bible John 3        (paged chapter reader)
#   savedverses              list verses you've saved from the chapter reader
#
# Credentials live in:  %USERPROFILE%\.lsm-verse.json
#   { "appid": "YOUR_APPID", "token": "YOUR_TOKEN" }
# Register at https://api.lsm.org to get an appid + token.
#
# Saved verses are stored in: %USERPROFILE%\.lsm-saved-verses.json
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
        # Decode the response as UTF-8 explicitly. Invoke-RestMethod on Windows
        # PowerShell 5.1 falls back to Latin-1 when the response has no charset,
        # which mangles the (c) in the copyright attribution into "A(c)".
        # -UseBasicParsing keeps 5.1 from invoking the Internet Explorer engine,
        # which fails outright on machines where IE was never configured.
        $response = Invoke-WebRequest -Uri $url -Headers $authHeader -TimeoutSec 15 -UseBasicParsing
        $json     = [Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
        return $json | ConvertFrom-Json
    } catch {
        Write-Host "Request failed: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function verse {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Reference
    )

    if (-not $Reference -or $Reference.Count -eq 0) {
        Write-Host "Usage: verse <reference>    e.g.  verse John 3:16" -ForegroundColor Yellow
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
        Write-Host $v.text
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

function Save-LsmVerse {
    # Stores only the reference, never the verse text - api.lsm.org's terms
    # of service prohibit storing any amount of the Recovery Version text for
    # offline use. The text is re-fetched live every time savedverses runs.
    param([string]$Reference)

    $storePath = Join-Path $HOME ".lsm-saved-verses.json"
    $saved = @()
    if (Test-Path $storePath) {
        try { $saved = @(Get-Content $storePath -Raw | ConvertFrom-Json) } catch { $saved = @() }
    }
    if ($saved | Where-Object { $_.ref -eq $Reference }) {
        Write-Host "Already saved: $Reference" -ForegroundColor Yellow
        return
    }
    $saved += [PSCustomObject]@{
        ref     = $Reference
        savedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $saved | ConvertTo-Json -Depth 5 | Set-Content -Path $storePath -Encoding utf8
    Write-Host "Saved $Reference" -ForegroundColor Green
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
                Write-Host $verseObj.text
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
                13 { Write-Host ""; return @{ Action = "Submit"; Text = $buffer } } # Enter
                8  {
                    if ($buffer.Length -gt 0) {
                        $buffer = $buffer.Substring(0, $buffer.Length - 1)
                        Write-Host "`b `b" -NoNewline
                    }
                }
                default {
                    $ch = $keyInfo.Character
                    if ($ch -and [int]$ch -ge 32 -and [int]$ch -ne 127) {
                        $buffer += $ch
                        Write-Host $ch -NoNewline
                    }
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

function Write-BibleVerseLine {
    # Prints a verse with its number, wrapping long text with a hanging
    # indent so continuation lines line up under the verse text, not the number.
    param([string]$Number, [string]$Text, [int]$Width)

    $prefix = "{0,3}  " -f $Number
    $indent = " " * $prefix.Length
    $lines  = @(Get-BibleWrappedLines -Text $Text -PrefixLength $prefix.Length -Width $Width)

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq 0) {
            Write-Host $prefix -ForegroundColor Yellow -NoNewline
        } else {
            Write-Host $indent -NoNewline
        }
        Write-Host $lines[$i]
    }
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
        $availableLines = [Math]::Max(3, $termHeight - 9)

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
        Write-Host "Up/Down arrow = scroll one verse   |   type another reference to jump there, e.g. John 4" -ForegroundColor DarkGray

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
                        $verseNum = Read-Host "Enter verse number to save"
                        $match = $verses | Where-Object { $_.ref -match ":$verseNum(-\d+)?$" } | Select-Object -First 1
                        if ($match) {
                            Save-LsmVerse -Reference $match.ref
                        } else {
                            Write-Host "Verse $verseNum not found on this chapter." -ForegroundColor Red
                        }
                        Read-Host "Press Enter to continue" | Out-Null
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
