<#
.SYNOPSIS
    blamscan - read campaign progress out of a Halo: Campaign Evolved save file.

.DESCRIPTION
    Halo: Campaign Evolved (2026) stores per-mission progress as Unreal
    GameplayTags inside its Xbox "Connected Storage" save. The in-game UI and
    the Xbox achievement API only expose an aggregate percentage, so you can
    see that you are at 92% without knowing WHICH mission you still owe.

    blamscan reads the save directly and prints the full matrix: difficulty
    completions, Remix, Remix deathless, skulls and terminals - per Xbox
    account, per mission.

    Read-only. The save file is never written to.

.PARAMETER SavePath
    Path to a save blob or to a "wgs" folder. Autodetected when omitted.

.PARAMETER Account
    Only report this XUID (decimal). Default: every account found.

.PARAMETER Section
    What to print: All, Missions, Skulls, Terminals. Default All.

.PARAMETER Json
    Also write the parsed result as JSON to this path.

.PARAMETER Raw
    Print every gameplay tag found, unparsed.

.EXAMPLE
    .\blamscan.ps1
    Autodetect and print everything.

.EXAMPLE
    .\blamscan.ps1 -Section Missions -Json progress.json

.LINK
    https://github.com/ThiloMeyer/blamscan
#>

[CmdletBinding()]
param(
    [string]$SavePath,
    [string]$Account,
    [ValidateSet('All', 'Missions', 'Skulls', 'Terminals')]
    [string]$Section = 'All',
    [string]$Json,
    [switch]$Raw
)

$ErrorActionPreference = 'Stop'

# --- constants --------------------------------------------------------------

# Package family name of Halo: Campaign Evolved. The name is opaque; the game
# is identified reliably by the string "HaloCampaignEvolved" inside
# containers.index, which is what the fallback search uses.
$PackageFamilyName = 'Microsoft.198377053870B_8wekyb3d8bbwe'

$Difficulties = @('Easy', 'Normal', 'Heroic', 'Legendary', 'Remix', 'Remix.Deathless')

$FallbackMissions = @(
    @{ id = 'a15'; name = 'The Pillar of Autumn';         kind = 'main'  }
    @{ id = 'a30'; name = 'Halo';                          kind = 'main'  }
    @{ id = 'a50'; name = 'The Truth and Reconciliation';  kind = 'main'  }
    @{ id = 'b30'; name = 'The Silent Cartographer';       kind = 'main'  }
    @{ id = 'b40'; name = 'Assault on the Control Room';   kind = 'main'  }
    @{ id = 'c10'; name = '343 Guilty Spark';              kind = 'main'  }
    @{ id = 'c20'; name = 'The Library';                   kind = 'main'  }
    @{ id = 'c40'; name = 'Two Betrayals';                 kind = 'main'  }
    @{ id = 'd20'; name = 'Keyes';                         kind = 'main'  }
    @{ id = 'd40'; name = 'The Maw';                       kind = 'main'  }
    @{ id = 'e10'; name = 'Bonus mission (e10)';           kind = 'bonus' }
    @{ id = 'e20'; name = 'Bonus mission (e20)';           kind = 'bonus' }
    @{ id = 'e30'; name = 'Bonus mission (e30)';           kind = 'bonus' }
)

# --- mission table ----------------------------------------------------------

function Get-MissionTable {
    $file = Join-Path $PSScriptRoot 'data\missions.json'
    if (Test-Path $file) {
        try {
            $data = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data.missions) {
                return @($data.missions | ForEach-Object {
                    @{ id = $_.id; name = $_.name; kind = $_.kind }
                })
            }
        } catch {
            Write-Warning "data\missions.json unreadable, using built-in table: $($_.Exception.Message)"
        }
    }
    return $FallbackMissions
}

# --- save discovery ---------------------------------------------------------

function Find-SaveRoot {
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "Path not found: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }

    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    $direct   = Join-Path $packages "$PackageFamilyName\SystemAppData\wgs"
    if (Test-Path $direct) { return $direct }

    Write-Verbose 'Default package path missing, scanning all Xbox packages.'
    foreach ($pkg in Get-ChildItem $packages -Directory -ErrorAction SilentlyContinue) {
        $wgs = Join-Path $pkg.FullName 'SystemAppData\wgs'
        if (-not (Test-Path $wgs)) { continue }
        $index = Get-ChildItem $wgs -Filter 'containers.index' -Recurse -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if (-not $index) { continue }
        $text = [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($index.FullName))
        if ($text -match 'HaloCampaignEvolved') { return $wgs }
    }

    throw 'No Halo: Campaign Evolved save found. Either the game was never played on this PC, or it was only played on an Xbox console (in which case the save lives in the cloud only).'
}

# --- gamertag lookup --------------------------------------------------------

function Get-GamertagMap {
    $map  = @{}
    $auth = Join-Path $env:LOCALAPPDATA 'Meteorite\Saved\AuthHaloStorage.json'
    if (-not (Test-Path $auth)) { return $map }
    try {
        $json = Get-Content $auth -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($entry in $json.UserAuthData.PSObject.Properties) {
            $map[[string]$entry.Value.Xid] = [string]$entry.Value.Gamertag
        }
    } catch {
        Write-Verbose "AuthHaloStorage.json unreadable: $($_.Exception.Message)"
    }
    return $map
}

# --- tag extraction ---------------------------------------------------------

function Get-TagsFromFile {
    param([string]$Path)
    # Tags are stored as plain ASCII inside the GVAS blob. Pulling them out
    # with a regex avoids having to implement a full GVAS parser, and survives
    # schema changes between game patches.
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
    return [regex]::Matches($text, 'Blam\.[A-Za-z0-9_.]+') |
           ForEach-Object { $_.Value } |
           Sort-Object -Unique
}

function Get-AccountSaves {
    param([string]$Root)

    $item = Get-Item $Root
    if (-not $item.PSIsContainer) {
        return @([pscustomobject]@{ Xuid = 'n/a'; File = $item; Tags = @(Get-TagsFromFile $item.FullName) })
    }

    $results = @()
    foreach ($dir in Get-ChildItem $Root -Directory) {

        $xuid = 'unknown'
        if ($dir.Name -match '^([0-9A-Fa-f]{16})_') {
            # Connected-storage folders are named <XUID-as-hex>_<SCID>.
            try { $xuid = [string][Convert]::ToUInt64($Matches[1], 16) } catch { }
        }

        $best = $null
        $bestTags = @()
        $candidates = Get-ChildItem $dir.FullName -Recurse -File |
                      Where-Object { $_.Name -notmatch '^(containers\.index|container\.\d+)$' -and $_.Length -lt 20MB }

        foreach ($file in $candidates) {
            $tags = @(Get-TagsFromFile $file.FullName)
            if ($tags.Count -gt $bestTags.Count) { $best = $file; $bestTags = $tags }
        }

        if ($best) {
            $results += [pscustomobject]@{ Xuid = $xuid; File = $best; Tags = $bestTags }
        }
    }
    return $results
}

# --- parsing ----------------------------------------------------------------

function ConvertTo-Progress {
    param([string[]]$Tags, [array]$Missions)

    $completion = @{}
    foreach ($m in $Missions) {
        $row = @{}
        foreach ($d in $Difficulties) { $row[$d] = $false }
        $completion[$m.id] = $row
    }

    $skulls    = [System.Collections.Generic.List[string]]::new()
    $terminals = [System.Collections.Generic.List[string]]::new()
    $unlocked  = [System.Collections.Generic.List[string]]::new()
    $unknown   = [System.Collections.Generic.List[string]]::new()

    foreach ($tag in $Tags) {
        switch -Regex ($tag) {
            '^Blam\.Progress\.Mission\.Completion\.Remix\.Deathless\.(.+)$' {
                if ($completion.ContainsKey($Matches[1])) { $completion[$Matches[1]]['Remix.Deathless'] = $true }
                else { $unknown.Add($tag) }
                break
            }
            '^Blam\.Progress\.Mission\.Completion\.(Easy|Normal|Heroic|Legendary|Remix)\.(.+)$' {
                if ($completion.ContainsKey($Matches[2])) { $completion[$Matches[2]][$Matches[1]] = $true }
                else { $unknown.Add($tag) }
                break
            }
            '^Blam\.Progress\.Mission\.Completion\.unlock_(.+)$' { $unlocked.Add($Matches[1]);  break }
            '^Blam\.Skull\.(.+)$'                               { $skulls.Add($Matches[1]);    break }
            '^Blam\.Terminal\.terminal_(.+)$'                   { $terminals.Add($Matches[1]); break }
            '^Blam\.Progress\.Mission\.InsertionPoints\.'        { break }  # checkpoints, not progress
            default                                             { $unknown.Add($tag) }
        }
    }

    return [pscustomobject]@{
        Completion = $completion
        Skulls     = @($skulls    | Sort-Object)
        Terminals  = @($terminals | Sort-Object)
        Unlocked   = @($unlocked  | Sort-Object)
        Unknown    = @($unknown   | Sort-Object)
    }
}

# --- output -----------------------------------------------------------------

function Write-MissionMatrix {
    param($Progress, [array]$Missions)

    $header = '{0,-3} {1,-32}' -f '#', 'Mission'
    foreach ($d in $Difficulties) { $header += ' {0,-7}' -f $d.Replace('Remix.Deathless', 'Rmx-DL').Replace('Legendary', 'Legend') }
    Write-Host ''
    Write-Host $header -ForegroundColor Cyan
    Write-Host ('-' * $header.Length) -ForegroundColor DarkGray

    $i = 0
    foreach ($m in $Missions) {
        $i++
        $line = '{0,-3} {1,-32}' -f $i, $m.name
        foreach ($d in $Difficulties) {
            $line += ' {0,-7}' -f $(if ($Progress.Completion[$m.id][$d]) { 'x' } else { '.' })
        }
        $done = $Progress.Completion[$m.id]['Remix.Deathless']
        Write-Host $line -ForegroundColor $(if ($done) { 'Gray' } else { 'Yellow' })
    }

    Write-Host ('-' * $header.Length) -ForegroundColor DarkGray
    $totals = '{0,-3} {1,-32}' -f '', 'completed'
    foreach ($d in $Difficulties) {
        $n = @($Missions | Where-Object { $Progress.Completion[$_.id][$d] }).Count
        $totals += ' {0,-7}' -f "$n/$($Missions.Count)"
    }
    Write-Host $totals -ForegroundColor Cyan

    foreach ($d in $Difficulties) {
        $missing = @($Missions | Where-Object { -not $Progress.Completion[$_.id][$d] })
        if ($missing.Count -gt 0 -and $missing.Count -le 4) {
            Write-Host ("  {0,-16} still missing: {1}" -f $d, (($missing | ForEach-Object { "$($_.name) [$($_.id)]" }) -join ', ')) -ForegroundColor Yellow
        }
    }
}

# --- main -------------------------------------------------------------------

$missions = Get-MissionTable
$root     = Find-SaveRoot -Explicit $SavePath
$tagMap   = Get-GamertagMap
$saves    = @(Get-AccountSaves -Root $root)

Write-Host ''
Write-Host 'blamscan - Halo: Campaign Evolved save reader' -ForegroundColor Cyan
Write-Host "source: $root" -ForegroundColor DarkGray

if ($saves.Count -eq 0) { Write-Host 'No save data found in that location.' -ForegroundColor Red; return }
if ($Account) { $saves = @($saves | Where-Object { $_.Xuid -eq $Account }) }
if ($saves.Count -eq 0) { Write-Host "No save data for XUID $Account." -ForegroundColor Red; return }

$export = @()

foreach ($save in $saves) {

    $gamertag = if ($tagMap.ContainsKey($save.Xuid)) { $tagMap[$save.Xuid] } else { $null }
    $progress = ConvertTo-Progress -Tags $save.Tags -Missions $missions

    Write-Host ''
    Write-Host ("=== XUID {0}{1} ===" -f $save.Xuid, $(if ($gamertag) { "  ($gamertag)" } else { '' })) -ForegroundColor Cyan
    Write-Host ("last written: {0}   tags: {1}" -f $save.File.LastWriteTime, $save.Tags.Count) -ForegroundColor DarkGray

    if ($Section -in 'All', 'Missions') { Write-MissionMatrix -Progress $progress -Missions $missions }

    if ($Section -in 'All', 'Skulls') {
        Write-Host ''
        Write-Host ("Skulls collected: {0}" -f $progress.Skulls.Count) -ForegroundColor Cyan
        if ($progress.Skulls.Count) { Write-Host ('  ' + ($progress.Skulls -join ', ')) }
    }

    if ($Section -in 'All', 'Terminals') {
        Write-Host ''
        Write-Host ("Terminals found: {0}" -f $progress.Terminals.Count) -ForegroundColor Cyan
        if ($progress.Terminals.Count) { Write-Host ('  ' + ($progress.Terminals -join ', ')) }
    }

    if ($progress.Unknown.Count) {
        Write-Host ''
        Write-Host ("Unrecognised tags ({0}) - the game may have been patched:" -f $progress.Unknown.Count) -ForegroundColor DarkYellow
        $progress.Unknown | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
    }

    if ($Raw) {
        Write-Host ''
        Write-Host 'All tags:' -ForegroundColor Cyan
        $save.Tags | ForEach-Object { Write-Host "  $_" }
    }

    $export += [pscustomobject]@{
        xuid       = $save.Xuid
        gamertag   = $gamertag
        savedAt    = $save.File.LastWriteTime.ToString('o')
        completion = $progress.Completion
        skulls     = $progress.Skulls
        terminals  = $progress.Terminals
        unlocked   = $progress.Unlocked
        unknown    = $progress.Unknown
    }
}

if ($Json) {
    $export | ConvertTo-Json -Depth 8 | Set-Content -Path $Json -Encoding UTF8
    Write-Host ''
    Write-Host "JSON written to $Json" -ForegroundColor Green
}

Write-Host ''
