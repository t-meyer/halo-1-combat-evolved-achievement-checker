<#
.SYNOPSIS
    halo-1-combat-evolved-achievement-checker - read campaign progress out of a Halo: Campaign Evolved save.

.DESCRIPTION
    Halo: Campaign Evolved (2026) stores per-mission progress as Unreal
    GameplayTags inside its Xbox "Connected Storage" save. The in-game UI and
    the Xbox achievement API only expose an aggregate percentage, so you can
    see that you are at 92% without knowing WHICH mission you still owe.

    It reads the save directly and prints the full matrix: difficulty
    completions, Remix, Remix deathless, skulls and terminals - per Xbox
    account, per mission. Completion sets are read from the save rather than
    hardcoded, so a set the game adds later shows up as its own column.

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

.PARAMETER DeepScan
    Search the whole user profile and Steam for the save instead of the
    known locations only. Slow; use it when autodetection finds nothing.

.EXAMPLE
    .\halo-1-combat-evolved-achievement-checker.ps1
    Autodetect and print everything.

.EXAMPLE
    .\halo-1-combat-evolved-achievement-checker.ps1 -Section Missions -Json progress.json

.LINK
    https://github.com/t-meyer/halo-1-combat-evolved-achievement-checker
#>

[CmdletBinding()]
param(
    [string]$SavePath,
    [string]$Account,
    [ValidateSet('All', 'Missions', 'Skulls', 'Terminals')]
    [string]$Section = 'All',
    [string]$Json,
    [switch]$Raw,
    [switch]$DeepScan
)

$ErrorActionPreference = 'Stop'

# --- constants --------------------------------------------------------------

# Package family name of Halo: Campaign Evolved. The name is opaque; the game
# is identified reliably by the string "HaloCampaignEvolved" inside
# containers.index, which is what the fallback search uses.
$PackageFamilyName = 'Microsoft.198377053870B_8wekyb3d8bbwe'

# Completion sets known today, in the order they are printed. The save is the
# authority: any further set it contains (a LASO column, say) is discovered at
# parse time and appended, so a game patch needs no code change here.
$KnownCategories = @('Easy', 'Normal', 'Heroic', 'Legendary', 'Remix', 'Remix.Deathless')

$CategoryLabels = @{
    'Legendary'       = 'Legend'
    'Remix.Deathless' = 'Rmx-DL'
}

function Get-CategoryLabel {
    param([string]$Category)
    if ($CategoryLabels.ContainsKey($Category)) { return $CategoryLabels[$Category] }
    $label = $Category.Split('.')[-1]
    if ($label.Length -gt 7) { $label = $label.Substring(0, 7) }
    return $label
}

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
    # $PSScriptRoot is empty when the script text is pasted into a console
    # instead of being run as a file, and Join-Path rejects an empty -Path.
    $base = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $file = Join-Path $base 'data\missions.json'
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

$script:SearchLog = [System.Collections.Generic.List[string]]::new()

function Write-SearchLog {
    param([string]$Message)
    $script:SearchLog.Add($Message)
    Write-Verbose $Message
}

# Output of a failed search ends up pasted into public issues, so the Windows
# user name and XUIDs are masked.
function Format-SafePath {
    param([string]$Path)
    $p = $Path
    if ($env:USERPROFILE) { $p = $p -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%' }
    $p = $p -replace '(?i)(\\userdata\\)\d+', '$1<steamid>'
    return ($p -replace '\b[0-9A-Fa-f]{16}_', '<xuid>_')
}

function Read-SaveBytes {
    param([string]$Path)
    # The running game keeps its save open; without FileShare.ReadWrite the
    # read fails with "being used by another process".
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $buf  = New-Object byte[] $fs.Length
        $read = 0
        while ($read -lt $buf.Length) {
            $n = $fs.Read($buf, $read, $buf.Length - $read)
            if ($n -le 0) { break }
            $read += $n
        }
        return ,$buf
    } finally {
        $fs.Dispose()
    }
}

function Get-ProgressScore {
    param([IO.FileInfo]$File)
    try {
        $text = [Text.Encoding]::ASCII.GetString((Read-SaveBytes $File.FullName))
    } catch {
        Write-SearchLog "  unreadable: $(Format-SafePath $File.FullName) ($($_.Exception.Message))"
        return 0
    }
    return [regex]::Matches($text, 'Blam\.(Progress|Skull|Terminal)\.').Count
}

function Get-WgsCandidates {
    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    $roots    = [System.Collections.Generic.List[string]]::new()

    $direct = Join-Path $packages "$PackageFamilyName\SystemAppData\wgs"
    if (Test-Path $direct) {
        Write-SearchLog "[found] Xbox app package folder: $(Format-SafePath $direct)"
        $roots.Add($direct)
    } else {
        Write-SearchLog "[--]    Xbox app package folder missing: $(Format-SafePath $direct)"
    }

    # The package family name may differ between editions or regions, so every
    # package is checked for the game's name inside containers.index.
    $scanned = 0
    foreach ($pkg in Get-ChildItem $packages -Directory -ErrorAction SilentlyContinue) {
        $wgs = Join-Path $pkg.FullName 'SystemAppData\wgs'
        if (-not (Test-Path $wgs) -or $roots -contains $wgs) { continue }
        $scanned++
        foreach ($index in Get-ChildItem $wgs -Filter 'containers.index' -Recurse -File -ErrorAction SilentlyContinue) {
            try { $bytes = Read-SaveBytes $index.FullName } catch { continue }
            $text = [Text.Encoding]::Unicode.GetString($bytes) + [Text.Encoding]::ASCII.GetString($bytes)
            if ($text -match 'HaloCampaignEvolved') {
                Write-SearchLog "[found] Halo package under another name: $($pkg.Name)"
                $roots.Add($wgs)
                break
            }
        }
    }
    Write-SearchLog "        $scanned other packages with Connected Storage checked"

    $result = @()
    foreach ($wgs in $roots) {
        $best = $null; $bestScore = 0
        $files = Get-ChildItem $wgs -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -notmatch '^(containers\.index|container\.\d+)$' -and $_.Length -lt 20MB }
        foreach ($f in $files) {
            $score = Get-ProgressScore $f
            if ($score -gt $bestScore -or ($score -eq $bestScore -and $score -gt 0 -and $f.LastWriteTime -gt $best.LastWriteTime)) {
                $best = $f; $bestScore = $score
            }
        }
        $accounts = @(Get-ChildItem $wgs -Directory -ErrorAction SilentlyContinue).Count
        if ($best) {
            Write-SearchLog "        $accounts account folder(s), progress blob with $bestScore tags, last written $($best.LastWriteTime)"
            $result += [pscustomobject]@{ Path = $wgs; File = $best; Score = $bestScore; Source = 'Xbox app / Game Pass' }
        } else {
            Write-SearchLog "[empty] $accounts account folder(s), $(@($files).Count) file(s), none holds progress tags"
        }
    }
    return $result
}

function Get-OtherSaveRoots {
    param([switch]$Deep)

    $roots   = [System.Collections.Generic.List[string]]::new()
    $userDir = $env:USERPROFILE
    $named   = '(?i)halo|meteorite|343'

    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam -and ${env:ProgramFiles(x86)}) { $steam = Join-Path ${env:ProgramFiles(x86)} 'Steam' }
    $steamUser = if ($steam) { Join-Path ($steam -replace '/', '\') 'userdata' } else { $null }
    if ($steamUser -and (Test-Path $steamUser)) {
        Write-SearchLog "[found] Steam userdata: $(Format-SafePath $steamUser)"
        $roots.Add($steamUser)
    } else {
        Write-SearchLog '[--]    Steam not installed (no userdata folder)'
    }

    $meteorite = Join-Path $env:LOCALAPPDATA 'Meteorite'
    if (Test-Path $meteorite) {
        Write-SearchLog "[found] game data folder: $(Format-SafePath $meteorite) - the game has run under this Windows account"
    } else {
        Write-SearchLog "[--]    game data folder missing: $(Format-SafePath $meteorite) - the game has never run under this Windows account"
    }

    $bases = @($env:LOCALAPPDATA, $env:APPDATA, (Join-Path $userDir 'AppData\LocalLow'),
               (Join-Path $userDir 'Saved Games'), (Join-Path $userDir 'Documents\My Games'),
               [Environment]::GetFolderPath('MyDocuments')) |
             Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    if ($Deep) {
        foreach ($b in $bases) { $roots.Add($b) }
    } else {
        foreach ($b in $bases) {
            Get-ChildItem $b -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $named } |
                ForEach-Object { $roots.Add($_.FullName) }
        }
    }
    return $roots
}

function Get-LooseCandidates {
    param([string[]]$Roots, [string[]]$Skip, [switch]$Deep)

    $skipExt = '(?i)\.(film|dll|exe|pak|ucas|utoc|png|jpg|jpeg|dds|log|ini|mp4|webm|db|sqlite|ldb|cache)$'
    $result  = @()
    foreach ($root in $Roots) {
        if ($Deep) { Write-Host "  scanning $(Format-SafePath $root) ..." -ForegroundColor DarkGray }
        $files = Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Length -ge 64 -and $_.Length -le 5MB -and $_.Name -notmatch $skipExt }
        $count = 0
        foreach ($f in $files) {
            $count++
            $inWgs = $false
            foreach ($s in $Skip) { if ($f.FullName.StartsWith($s, [StringComparison]::OrdinalIgnoreCase)) { $inWgs = $true; break } }
            if ($inWgs) { continue }
            $score = Get-ProgressScore $f
            if ($score -gt 0) {
                Write-SearchLog "[found] $score progress tags in $(Format-SafePath $f.FullName)"
                $result += [pscustomobject]@{ Path = $f.FullName; File = $f; Score = $score; Source = 'loose save file' }
            }
        }
        Write-SearchLog "        $count file(s) checked under $(Format-SafePath $root)"
    }
    return $result
}

function Write-SearchReport {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                 [Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Host ''
    Write-Host 'No Halo: Campaign Evolved save found. What was checked:' -ForegroundColor Red
    Write-Host ("  PowerShell {0}, {1}, running as administrator: {2}" -f $PSVersionTable.PSVersion,
                $(if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }), $admin) -ForegroundColor DarkGray
    foreach ($line in $script:SearchLog) { Write-Host "  $line" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host 'What to try:' -ForegroundColor Yellow
    if (-not (Test-Path (Join-Path $env:LOCALAPPDATA 'Meteorite'))) {
        Write-Host '  - The game has never started under the Windows account this window runs as.' -ForegroundColor Yellow
        Write-Host '    If you opened PowerShell "as administrator" with a different account, open it normally instead.' -ForegroundColor Yellow
    }
    Write-Host '  - Run again with -DeepScan. It searches your whole profile and Steam for the save (takes a few minutes).' -ForegroundColor Yellow
    Write-Host '  - If you know where the save is, pass it with -SavePath.' -ForegroundColor Yellow
    Write-Host '  - Still nothing: open an issue and paste everything above. User name and XUID are masked.' -ForegroundColor Yellow
    Write-Host ''
}

function Find-SaveRoot {
    param([string]$Explicit, [switch]$Deep)

    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "Path not found: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }

    $candidates = @(Get-WgsCandidates)
    $skip       = @($candidates | ForEach-Object { $_.Path })
    $loose      = @(Get-LooseCandidates -Roots (Get-OtherSaveRoots -Deep:$Deep) -Skip $skip -Deep:$Deep)
    $candidates = @($candidates) + @($loose)

    if ($candidates.Count -eq 0) {
        Write-SearchReport
        throw 'No Halo: Campaign Evolved save found (see the list above).'
    }

    $pick = $candidates | Sort-Object { $_.File.LastWriteTime } -Descending | Select-Object -First 1
    if ($candidates.Count -gt 1) {
        Write-Host ''
        Write-Host 'Several saves found, using the most recently written one:' -ForegroundColor Yellow
        foreach ($c in $candidates | Sort-Object { $_.File.LastWriteTime } -Descending) {
            $mark = if ($c -eq $pick) { '*' } else { ' ' }
            Write-Host ("  {0} {1:yyyy-MM-dd HH:mm}  {2,-20} {3}" -f $mark, $c.File.LastWriteTime, $c.Source, (Format-SafePath $c.Path)) -ForegroundColor Yellow
        }
        Write-Host '  Pick another one with -SavePath.' -ForegroundColor Yellow
    }
    return $pick.Path
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
    $text = [Text.Encoding]::ASCII.GetString((Read-SaveBytes $Path))
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

    $missionIds = @{}
    foreach ($m in $Missions) { $missionIds[$m.id] = $true }

    $skulls    = [System.Collections.Generic.List[string]]::new()
    $terminals = [System.Collections.Generic.List[string]]::new()
    $unlocked  = [System.Collections.Generic.List[string]]::new()
    $unknown   = [System.Collections.Generic.List[string]]::new()
    $earned    = [System.Collections.Generic.List[object]]::new()
    $extra     = [System.Collections.Generic.List[string]]::new()

    foreach ($tag in $Tags) {
        switch -Regex ($tag) {
            '^Blam\.Progress\.Mission\.Completion\.unlock_(.+)$' { $unlocked.Add($Matches[1]); break }
            '^Blam\.Progress\.Mission\.Completion\.(.+)$' {
                # What follows is <category>.<mission id>, and the category may
                # itself contain dots (Remix.Deathless). The mission id is the
                # last segment, so the category is whatever precedes it - that
                # is how a set the game adds later ends up with its own column.
                $rest = $Matches[1]
                $cut  = $rest.LastIndexOf('.')
                $id   = if ($cut -ge 0) { $rest.Substring($cut + 1) } else { '' }
                if ($cut -gt 0 -and $missionIds.ContainsKey($id)) {
                    $category = $rest.Substring(0, $cut)
                    $earned.Add([pscustomobject]@{ Category = $category; Mission = $id })
                    if ($KnownCategories -notcontains $category -and $extra -notcontains $category) {
                        $extra.Add($category)
                    }
                } else {
                    $unknown.Add($tag)
                }
                break
            }
            '^Blam\.Skull\.(.+)$'                        { $skulls.Add($Matches[1]);    break }
            '^Blam\.Terminal\.terminal_(.+)$'            { $terminals.Add($Matches[1]); break }
            '^Blam\.Progress\.Mission\.InsertionPoints\.' { break }  # checkpoints, not progress
            default                                        { $unknown.Add($tag) }
        }
    }

    $categories = @($KnownCategories) + @($extra | Sort-Object)

    $completion = @{}
    foreach ($m in $Missions) {
        $row = @{}
        foreach ($c in $categories) { $row[$c] = $false }
        $completion[$m.id] = $row
    }
    foreach ($e in $earned) { $completion[$e.Mission][$e.Category] = $true }

    return [pscustomobject]@{
        Categories = $categories
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

    $categories = $Progress.Categories

    $header = '{0,-3} {1,-32}' -f '#', 'Mission'
    foreach ($c in $categories) { $header += ' {0,-7}' -f (Get-CategoryLabel $c) }
    Write-Host ''
    Write-Host $header -ForegroundColor Cyan
    Write-Host ('-' * $header.Length) -ForegroundColor DarkGray

    $i = 0
    foreach ($m in $Missions) {
        $i++
        $line = '{0,-3} {1,-32}' -f $i, $m.name
        foreach ($c in $categories) {
            $line += ' {0,-7}' -f $(if ($Progress.Completion[$m.id][$c]) { 'x' } else { '.' })
        }
        $complete = @($categories | Where-Object { -not $Progress.Completion[$m.id][$_] }).Count -eq 0
        Write-Host $line -ForegroundColor $(if ($complete) { 'Gray' } else { 'Yellow' })
    }

    Write-Host ('-' * $header.Length) -ForegroundColor DarkGray
    $totals = '{0,-3} {1,-32}' -f '', 'completed'
    foreach ($c in $categories) {
        $n = @($Missions | Where-Object { $Progress.Completion[$_.id][$c] }).Count
        $totals += ' {0,-7}' -f "$n/$($Missions.Count)"
    }
    Write-Host $totals -ForegroundColor Cyan

    foreach ($c in $categories) {
        $missing = @($Missions | Where-Object { -not $Progress.Completion[$_.id][$c] })
        if ($missing.Count -gt 0 -and $missing.Count -le 4) {
            Write-Host ("  {0,-16} still missing: {1}" -f $c, (($missing | ForEach-Object { "$($_.name) [$($_.id)]" }) -join ', ')) -ForegroundColor Yellow
        }
    }

    $discovered = @($categories | Where-Object { $KnownCategories -notcontains $_ })
    if ($discovered.Count) {
        Write-Host ("  extra completion sets in this save: {0}" -f ($discovered -join ', ')) -ForegroundColor Cyan
    }
}

# --- main -------------------------------------------------------------------

$missions = Get-MissionTable
$root     = Find-SaveRoot -Explicit $SavePath -Deep:$DeepScan
$tagMap   = Get-GamertagMap
$saves    = @(Get-AccountSaves -Root $root)

Write-Host ''
Write-Host 'Halo 1: Combat Evolved Achievement Checker - Campaign Evolved save reader' -ForegroundColor Cyan
Write-Host "source: $(Format-SafePath $root)" -ForegroundColor DarkGray

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
