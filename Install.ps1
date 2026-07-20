<#
.SYNOPSIS
    One-time setup for the Bible Verse Lookup Tool.

.DESCRIPTION
    1. Copies this folder's BibleVerseTool.ps1 next to your PowerShell profile
       (if it isn't already there).
    2. Adds a line to your PowerShell profile ($PROFILE) that dot-sources it,
       so the "verse", "bible", and "savedverses" commands are available in
       every new PowerShell window. Safe to re-run - it will not add the line
       twice.
    3. Creates your personal credentials file (%USERPROFILE%\.lsm-verse.json)
       from the example template if it does not already exist.

.NOTES
    This script does NOT fill in your API token for you. Open the credentials
    file afterwards and paste in your own appid/token from https://api.lsm.org.
#>

$here       = $PSScriptRoot
$toolSource = Join-Path $here "BibleVerseTool.ps1"
$profileDir = Split-Path $PROFILE -Parent
$toolDest   = Join-Path $profileDir "BibleVerseTool.ps1"

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

Copy-Item -Path $toolSource -Destination $toolDest -Force
Write-Host "Copied BibleVerseTool.ps1 to $toolDest" -ForegroundColor Green

if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$dotSourceLine = '. "$PSScriptRoot\BibleVerseTool.ps1"'
$profileText   = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileText -notmatch [regex]::Escape("BibleVerseTool.ps1")) {
    try {
        Add-Content -Path $PROFILE -Value "`n# Bible Verse Lookup Tool`n$dotSourceLine`n" -ErrorAction Stop
    } catch {
        Write-Host "Could not write to $PROFILE : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Add this line to it yourself:  $dotSourceLine" -ForegroundColor Yellow
    }

    $verifyText = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($verifyText -match [regex]::Escape("BibleVerseTool.ps1")) {
        Write-Host "Added dot-source line to your profile: $PROFILE" -ForegroundColor Green
    } else {
        Write-Host "Profile still doesn't reference BibleVerseTool.ps1 after writing - something (maybe OneDrive sync) blocked the update." -ForegroundColor Red
        Write-Host "Open $PROFILE yourself and add this line:  $dotSourceLine" -ForegroundColor Yellow
    }
} else {
    Write-Host "Profile already references BibleVerseTool.ps1 - left untouched." -ForegroundColor Yellow
}

$credPath = Join-Path $HOME ".lsm-verse.json"
if (-not (Test-Path $credPath)) {
    Copy-Item -Path (Join-Path $here ".lsm-verse.example.json") -Destination $credPath
    Write-Host "Created $credPath - open it and paste in your real appid/token." -ForegroundColor Yellow
} else {
    Write-Host "Credentials file already exists at $credPath - left untouched." -ForegroundColor Yellow
}

# The example file is tracked by git. If real credentials get typed into it by
# mistake instead of into $credPath, they are one "git push" away from being
# public - so say so loudly rather than letting it slide.
$examplePath = Join-Path $here ".lsm-verse.example.json"
try {
    $example = Get-Content $examplePath -Raw -ErrorAction Stop | ConvertFrom-Json
    if (($example.appid -and $example.appid -notlike "YOUR_*") -or
        ($example.token -and $example.token -notlike "YOUR_*")) {
        Write-Host ""
        Write-Host "WARNING: $examplePath appears to contain real credentials." -ForegroundColor Red
        Write-Host "That file is tracked by git - committing it would publish your token." -ForegroundColor Red
        Write-Host "Move them into $credPath and reset the example back to YOUR_APPID / YOUR_TOKEN." -ForegroundColor Yellow
    }
} catch {
    # Example file missing or unparseable - nothing to warn about.
}

Write-Host ""
Write-Host "Setup complete. Close and reopen PowerShell, then try:  verse John 3:16" -ForegroundColor Cyan
