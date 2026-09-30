# TwichUI: build a file version of your addon configuration, for friends you can't reach
# in game (other realms, or if they'd rather install a file).
#   1. In game: /pack > Find my addon settings > tick > Save my configuration
#   2. Log out (or /reload) so the game writes it to disk
#   3. Double-click make_pack.bat. A zip lands on your Desktop.
# Only your saved configuration is included: never ones friends sent you, and
# never your backups.

$ErrorActionPreference = 'Stop'
$addonDir   = Split-Path -Parent $PSScriptRoot
$addonName  = Split-Path -Leaf $addonDir
$flavorRoot = (Resolve-Path (Join-Path $addonDir '..\..\..')).Path
$svName     = "$addonName.lua"

Write-Host "Game folder: $flavorRoot"
$candidates = @(Get-ChildItem -LiteralPath (Join-Path $flavorRoot 'WTF\Account') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "SavedVariables\$svName" } |
    Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object { Get-Item -LiteralPath $_ } |
    Sort-Object LastWriteTime -Descending)

if ($candidates.Count -eq 0) {
    Write-Host "Couldn't find SavedVariables\$svName. Save your configuration in game (/pack), log out, and try again." -ForegroundColor Red
    exit 1
}
$sv = $candidates[0]
if ($candidates.Count -gt 1) { Write-Host "Several accounts found; using the most recent: $($sv.FullName)" }
Write-Host "Reading $($sv.FullName) (saved $($sv.LastWriteTime))"

# Keep only the TwichUIShareDB block, renamed to TwichUI_PackFile.
$lines = [IO.File]::ReadAllLines($sv.FullName)
$out  = New-Object System.Collections.Generic.List[string]
$keep = $false
foreach ($line in $lines) {
    if ($line -match '^[A-Za-z_][A-Za-z0-9_]* = ') {
        $keep = $line -match '^TwichUIShareDB = '
        if ($keep) { $line = $line -replace '^TwichUIShareDB = ', 'TwichUI_PackFile = ' }
    }
    if ($keep) { $out.Add($line) }
}
$text = [string]::Join("`n", $out)
if ($text -notmatch '\["pack"\]') {
    Write-Host "No saved configuration found yet. In game: /pack > Save my configuration, then log out and run this again." -ForegroundColor Red
    exit 1
}

$stage = Join-Path ([IO.Path]::GetTempPath()) ("TwichUI_" + [guid]::NewGuid().ToString('N'))
$dest  = Join-Path $stage $addonName
New-Item -ItemType Directory -Path $dest | Out-Null
$devOnly = @('tests', '.github', '.git', '.pkgmeta', '.gitignore', 'RELEASING.md')
Get-ChildItem -LiteralPath $addonDir -Force | Where-Object { $devOnly -notcontains $_.Name } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force }
$header = "-- TwichUI addon configuration file, built $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Replace this file to update it."
[IO.File]::WriteAllText((Join-Path $dest 'setup\PackFile.lua'), $header + "`n" + $text + "`n", (New-Object Text.UTF8Encoding($false)))

$desktop = [Environment]::GetFolderPath('Desktop')
$zip = Join-Path $desktop ("TwichUI-configuration-" + (Get-Date -Format 'yyyy-MM-dd') + ".zip")
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
Compress-Archive -LiteralPath $dest -DestinationPath $zip
Remove-Item -LiteralPath $stage -Recurse -Force

$mb = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 2)
Write-Host ""
Write-Host "Done: $zip ($mb MB)" -ForegroundColor Green
Write-Host "Friends unzip it into Interface\AddOns (replacing TwichUI), log in, and type /pack."
