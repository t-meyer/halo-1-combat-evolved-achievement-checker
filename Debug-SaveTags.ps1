<#
.SYNOPSIS
    Debug-SaveTags - list the gameplay tags in every save container, not just one.

.DESCRIPTION
    The main script reads one container per Xbox account: whichever holds the
    most tags, which in practice is Progress. This one opens every container,
    including the two ~1 MB CoreSave blobs nothing has parsed yet, and reports
    what each of them contains.

    Use it to answer questions the mission table cannot, such as whether the
    LASO playlist records anything of its own and, if so, where.

    Read-only. Nothing is written to the save, ever.

.PARAMETER SavePath
    Path to a "wgs" folder or to a single container. Autodetected when omitted.

.PARAMETER Pattern
    Regex for tags to call out separately. Default: laso|mythic.

.PARAMETER Export
    Write every tag of every container to this file, for sharing in an issue.
    Tags contain no XUID or gamertag, so the file is safe to post as-is.

.PARAMETER Baseline
    An earlier -Export file. Reports which tags have appeared and disappeared
    since, which is how you find out what a given activity actually writes:
    export, play the thing, export again against the first file.

.EXAMPLE
    .\Debug-SaveTags.ps1

.EXAMPLE
    .\Debug-SaveTags.ps1 -Pattern 'laso|mythic|skull' -Export tags.txt

.EXAMPLE
    .\Debug-SaveTags.ps1 -Export after.txt -Baseline before.txt

.LINK
    https://github.com/t-meyer/halo-1-combat-evolved-achievement-checker
#>

[CmdletBinding()]
param(
    [string]$SavePath,
    [string]$Pattern = 'laso|mythic',
    [string]$Export,
    [string]$Baseline
)

$ErrorActionPreference = 'Stop'

$PackageFamilyName = 'Microsoft.198377053870B_8wekyb3d8bbwe'

function Find-SaveRoot {
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "Path not found: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }

    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    $direct   = Join-Path $packages "$PackageFamilyName\SystemAppData\wgs"
    if (Test-Path $direct) { return $direct }

    foreach ($pkg in Get-ChildItem $packages -Directory -ErrorAction SilentlyContinue) {
        $wgs = Join-Path $pkg.FullName 'SystemAppData\wgs'
        if (-not (Test-Path $wgs)) { continue }
        $index = Get-ChildItem $wgs -Filter 'containers.index' -Recurse -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if (-not $index) { continue }
        $text = [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($index.FullName))
        if ($text -match 'HaloCampaignEvolved') { return $wgs }
    }

    throw 'No Halo: Campaign Evolved save found. Either the game was never played on this PC, or it was only played on an Xbox console.'
}

function Get-Tags {
    param([string]$Path)
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
    return @([regex]::Matches($text, 'Blam\.[A-Za-z0-9_.]+') |
             ForEach-Object { $_.Value } |
             Sort-Object -Unique)
}

# --- collect ----------------------------------------------------------------

$root = Find-SaveRoot -Explicit $SavePath
$item = Get-Item $root

$files = if ($item.PSIsContainer) {
    @(Get-ChildItem $root -Recurse -File |
      Where-Object { $_.Name -notmatch '^(containers\.index|container\.\d+)$' -and $_.Length -lt 20MB })
} else {
    @($item)
}

Write-Host ''
Write-Host 'Save container inventory' -ForegroundColor Cyan
Write-Host "source: $root" -ForegroundColor DarkGray
Write-Host "containers: $($files.Count)" -ForegroundColor DarkGray

$inventory = @()
foreach ($file in $files) {
    $tags = Get-Tags $file.FullName
    $inventory += [pscustomobject]@{
        File = $file.Name
        KB   = [int]($file.Length / 1KB)
        Tags = $tags.Count
        Hits = @($tags | Where-Object { $_ -match $Pattern }).Count
        All  = $tags
    }
}

Write-Host ''
($inventory | Sort-Object KB -Descending |
 Format-Table File, KB, Tags, Hits -AutoSize | Out-String).TrimEnd() | Write-Host

# --- what is in there -------------------------------------------------------

$all = @($inventory | ForEach-Object { $_.All } | Sort-Object -Unique)

Write-Host ''
Write-Host ("distinct tags across all containers: {0}" -f $all.Count) -ForegroundColor Cyan

Write-Host ''
Write-Host 'tag families:' -ForegroundColor Cyan
$all | ForEach-Object {
        # Group one level above the leaf, capped at four segments, so skulls
        # collapse to Blam.Skull while the Progress tree keeps its branches.
        $parts = $_ -split '\.'
        $keep  = [Math]::Max(2, [Math]::Min(4, $parts.Count - 1))
        ($parts[0..($keep - 1)]) -join '.'
    } |
    Group-Object | Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("  {0,5}  {1}" -f $_.Count, $_.Name) }

$sets = @{}
foreach ($tag in $all) {
    if ($tag -notmatch '^Blam\.Progress\.Mission\.Completion\.(.+)$') { continue }
    $rest = $Matches[1]
    if ($rest -like 'unlock_*') { continue }
    $cut = $rest.LastIndexOf('.')
    if ($cut -gt 0) { $sets[$rest.Substring(0, $cut)] = $true }
}

Write-Host ''
Write-Host 'completion sets:' -ForegroundColor Cyan
if ($sets.Count) {
    foreach ($set in ($sets.Keys | Sort-Object)) { Write-Host "  $set" }
} else {
    Write-Host '  none' -ForegroundColor Yellow
}

$hits = @($all | Where-Object { $_ -match $Pattern })
Write-Host ''
Write-Host ("tags matching /{0}/: {1}" -f $Pattern, $hits.Count) -ForegroundColor $(if ($hits.Count) { 'Green' } else { 'Yellow' })
foreach ($hit in $hits) { Write-Host "  $hit" }

if (-not $hits.Count) {
    Write-Host ''
    Write-Host 'Nothing matched. Either the save does not record it at all, or it is' -ForegroundColor DarkGray
    Write-Host 'stored under a name this pattern does not cover - try -Pattern with' -ForegroundColor DarkGray
    Write-Host 'something broader, or export the full list and read through it.' -ForegroundColor DarkGray
}

# --- what changed -----------------------------------------------------------

if ($Baseline) {
    if (-not (Test-Path $Baseline)) { throw "Baseline file not found: $Baseline" }
    $was = @(Get-Content $Baseline | ForEach-Object { $_.Trim() } | Where-Object { $_ -like 'Blam.*' } | Sort-Object -Unique)

    $added   = @($all | Where-Object { $was  -notcontains $_ })
    $removed = @($was | Where-Object { $all  -notcontains $_ })

    Write-Host ''
    Write-Host ("compared against {0} ({1} tags)" -f (Split-Path $Baseline -Leaf), $was.Count) -ForegroundColor Cyan

    Write-Host ("  appeared since: {0}" -f $added.Count) -ForegroundColor $(if ($added.Count) { 'Green' } else { 'DarkGray' })
    foreach ($tag in $added) { Write-Host "    + $tag" -ForegroundColor Green }

    if ($removed.Count) {
        Write-Host ("  gone since: {0}" -f $removed.Count) -ForegroundColor Yellow
        foreach ($tag in $removed) { Write-Host "    - $tag" -ForegroundColor Yellow }
    }

    if (-not $added.Count -and -not $removed.Count) {
        Write-Host '  the save is unchanged' -ForegroundColor DarkGray
    }
}

# --- export -----------------------------------------------------------------

if ($Export) {
    $lines = foreach ($entry in ($inventory | Sort-Object KB -Descending)) {
        "=== {0} ({1} KB, {2} tags) ===" -f $entry.File, $entry.KB, $entry.Tags
        $entry.All
        ''
    }
    $lines | Set-Content -Path $Export -Encoding ASCII
    Write-Host ''
    Write-Host "full tag list written to $Export" -ForegroundColor Green
}

Write-Host ''
