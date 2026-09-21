<#
.SYNOPSIS
    Debug-SaveTags - what every Halo: Campaign Evolved save container contains.

.DESCRIPTION
    The main script reads one container per Xbox account, whichever holds the
    most gameplay tags, and looks only at names beginning with "Blam.". This
    one opens every container, including the two ~1 MB CoreSave blobs, and with
    -Strings it reads every printable string rather than just the tags.

    That matters when the thing you are looking for is not a gameplay tag at
    all. A playlist or modifier flag may sit in the save as an ordinary GVAS
    property, under a name no tag pattern would ever match.

    The intended use is before-and-after: export, do the thing in game, export
    again against the first file, and read off what the game actually wrote.

    Read-only. Nothing is written to the save, ever.

.PARAMETER SavePath
    Path to a "wgs" folder or to a single container. Autodetected when omitted.

.PARAMETER Strings
    Collect every printable string, not just Blam tags. Reads each container
    both as single-byte and as UTF-16, because GVAS mixes the two.

.PARAMETER MinLength
    Shortest string to keep in -Strings mode. Default 6. Lower finds more and
    drags in more noise from binary data.

.PARAMETER Pattern
    Regex for entries to call out separately. Default: laso|mythic.

.PARAMETER Export
    Write everything found, per container, to this file. Gameplay tags carry no
    XUID or gamertag; in -Strings mode, skim the file before posting it.

.PARAMETER Baseline
    An earlier -Export file. Reports what has appeared and disappeared since.

.PARAMETER Inspect
    Regex for a name to dump in place: every container is searched, and the
    bytes around each match are printed as hex and text. That is how you read
    what a GVAS property actually is - the type name follows immediately after
    the property name, and a BoolProperty's value is the single byte after it.

.PARAMETER Around
    How many bytes after a match -Inspect prints. Default 80.

.PARAMETER Before
    How many bytes before a match -Inspect prints. Default 16. Raise it when a
    neighbouring name is cut off at the top of the dump.

.EXAMPLE
    .\Debug-SaveTags.ps1

.EXAMPLE
    .\Debug-SaveTags.ps1 -Strings -Export before.txt

.EXAMPLE
    .\Debug-SaveTags.ps1 -Strings -Export after.txt -Baseline before.txt

.EXAMPLE
    .\Debug-SaveTags.ps1 -Inspect 'IsLASO' -Before 128 -Around 256

.LINK
    https://github.com/t-meyer/halo-1-combat-evolved-achievement-checker
#>

[CmdletBinding()]
param(
    [string]$SavePath,
    [switch]$Strings,
    [int]$MinLength = 6,
    [string]$Pattern = 'laso|mythic',
    [string]$Export,
    [string]$Baseline,
    [string]$Inspect,
    [int]$Around = 80,
    [int]$Before = 16
)

$ErrorActionPreference = 'Stop'

$PackageFamilyName = 'Microsoft.198377053870B_8wekyb3d8bbwe'
$ShowLimit = 40

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

function Get-SaveStrings {
    param([string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    # Latin-1 maps every byte to one char, so bytes above 127 stay outside the
    # printable range below instead of being folded into "?" as ASCII would.
    $narrow = [Text.Encoding]::GetEncoding(28591).GetString($bytes)

    if (-not $Strings) {
        return @([regex]::Matches($narrow, 'Blam\.[A-Za-z0-9_.]+') |
                 ForEach-Object { $_.Value } | Sort-Object -Unique)
    }

    $printable = "[\x20-\x7E]{$MinLength,}"
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($narrow, $printable)) { $found.Add($m.Value) }

    # GVAS stores some strings as UTF-16, which the pass above sees only as
    # every other character, so read the same bytes that way too.
    $wide = [Text.Encoding]::Unicode.GetString($bytes)
    foreach ($m in [regex]::Matches($wide, $printable)) { $found.Add($m.Value) }

    return @($found | Sort-Object -Unique)
}

function Write-Capped {
    param([string[]]$Items, [string]$Colour = 'Gray', [string]$Indent = '  ')
    $shown = 0
    foreach ($item in $Items) {
        if ($shown -ge $ShowLimit) {
            Write-Host ("{0}... and {1} more, see -Export" -f $Indent, ($Items.Count - $ShowLimit)) -ForegroundColor DarkGray
            break
        }
        Write-Host "$Indent$item" -ForegroundColor $Colour
        $shown++
    }
}

function Write-HexDump {
    param([byte[]]$Bytes, [int]$Start, [int]$Length, [int]$Highlight)

    $end = [Math]::Min($Bytes.Length, $Start + $Length)
    for ($row = $Start; $row -lt $end; $row += 16) {
        $hex  = ''
        $text = ''
        for ($i = $row; $i -lt ($row + 16); $i++) {
            if ($i -ge $end) { $hex += '   '; continue }
            $b = $Bytes[$i]
            $hex  += '{0:x2} ' -f $b
            $text += $(if ($b -ge 0x20 -and $b -le 0x7E) { [char]$b } else { '.' })
        }
        $colour = $(if ($row -le $Highlight -and ($row + 16) -gt $Highlight) { 'Green' } else { 'Gray' })
        Write-Host ("    {0:x8}  {1} {2}" -f $row, $hex, $text) -ForegroundColor $colour
    }
}

function Show-Inspection {
    param([System.IO.FileInfo]$File, [string]$Match, [int]$Around, [int]$Before)

    $bytes  = [IO.File]::ReadAllBytes($File.FullName)
    $narrow = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    $wide   = [Text.Encoding]::Unicode.GetString($bytes)

    $offsets = @()
    foreach ($m in [regex]::Matches($narrow, $Match)) { $offsets += [pscustomobject]@{ At = $m.Index;     Width = 1 } }
    foreach ($m in [regex]::Matches($wide,   $Match)) { $offsets += [pscustomobject]@{ At = $m.Index * 2; Width = 2 } }
    if (-not $offsets.Count) { return 0 }

    foreach ($hit in ($offsets | Sort-Object At)) {
        $from = [Math]::Max(0, $hit.At - $Before)
        Write-Host ''
        Write-Host ("  {0} at offset {1} (0x{1:x}), {2}-byte characters" -f $File.Name, $hit.At, $hit.Width) -ForegroundColor Cyan
        Write-HexDump -Bytes $bytes -Start $from -Length ($Around + ($hit.At - $from)) -Highlight $hit.At
    }
    return $offsets.Count
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
Write-Host ("containers: {0}   mode: {1}" -f $files.Count, $(if ($Strings) { "all printable strings, min $MinLength chars" } else { 'Blam tags only' })) -ForegroundColor DarkGray

$inventory = @()
foreach ($file in $files) {
    $found = Get-SaveStrings -Path $file.FullName
    $inventory += [pscustomobject]@{
        File  = $file.Name
        KB    = [int]($file.Length / 1KB)
        Found = $found.Count
        Hits  = @($found | Where-Object { $_ -match $Pattern }).Count
        All   = $found
    }
}

Write-Host ''
($inventory | Sort-Object KB -Descending |
 Format-Table File, KB, Found, Hits -AutoSize | Out-String).TrimEnd() | Write-Host

$all = @($inventory | ForEach-Object { $_.All } | Sort-Object -Unique)
$tags = @($all | Where-Object { $_ -like 'Blam.*' })

Write-Host ''
Write-Host ("distinct entries: {0}   of them Blam tags: {1}" -f $all.Count, $tags.Count) -ForegroundColor Cyan

# --- what is in there -------------------------------------------------------

Write-Host ''
Write-Host 'tag families:' -ForegroundColor Cyan
$tags | ForEach-Object {
        # Group one level above the leaf, capped at four segments, so skulls
        # collapse to Blam.Skull while the Progress tree keeps its branches.
        $parts = $_ -split '\.'
        $keep  = [Math]::Max(2, [Math]::Min(4, $parts.Count - 1))
        ($parts[0..($keep - 1)]) -join '.'
    } |
    Group-Object | Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("  {0,5}  {1}" -f $_.Count, $_.Name) }

$sets = @{}
foreach ($tag in $tags) {
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
Write-Host ("entries matching /{0}/: {1}" -f $Pattern, $hits.Count) -ForegroundColor $(if ($hits.Count) { 'Green' } else { 'Yellow' })
Write-Capped -Items $hits -Colour Green

if (-not $hits.Count -and -not $Strings) {
    Write-Host ''
    Write-Host 'Nothing matched among the Blam tags. Try -Strings, which also reads' -ForegroundColor DarkGray
    Write-Host 'ordinary GVAS property names and the CoreSave blobs.' -ForegroundColor DarkGray
}

# --- what changed -----------------------------------------------------------

if ($Baseline) {
    if (-not (Test-Path $Baseline)) { throw "Baseline file not found: $Baseline" }

    $was = @(Get-Content $Baseline |
             Where-Object { $_ -and $_ -notmatch '^=== .* ===$' } |
             ForEach-Object { $_.TrimEnd() } |
             Sort-Object -Unique)

    $added   = @($all | Where-Object { $was -notcontains $_ })
    $removed = @($was | Where-Object { $all -notcontains $_ })

    Write-Host ''
    Write-Host ("compared against {0} ({1} entries)" -f (Split-Path $Baseline -Leaf), $was.Count) -ForegroundColor Cyan

    Write-Host ("  appeared since: {0}" -f $added.Count) -ForegroundColor $(if ($added.Count) { 'Green' } else { 'DarkGray' })
    Write-Capped -Items $added -Colour Green -Indent '    + '

    if ($removed.Count) {
        Write-Host ("  gone since: {0}" -f $removed.Count) -ForegroundColor Yellow
        Write-Capped -Items $removed -Colour Yellow -Indent '    - '
    }

    if (-not $added.Count -and -not $removed.Count) {
        Write-Host '  nothing changed' -ForegroundColor DarkGray
    }
}

# --- inspect ----------------------------------------------------------------

if ($Inspect) {
    Write-Host ''
    Write-Host ("inspecting /{0}/ in place:" -f $Inspect) -ForegroundColor Cyan
    $total = 0
    foreach ($file in $files) { $total += Show-Inspection -File $file -Match $Inspect -Around $Around -Before $Before }
    if (-not $total) {
        Write-Host '  no match in any container' -ForegroundColor Yellow
    }
}

# --- export -----------------------------------------------------------------

if ($Export) {
    $lines = foreach ($entry in ($inventory | Sort-Object KB -Descending)) {
        "=== {0} ({1} KB, {2} entries) ===" -f $entry.File, $entry.KB, $entry.Found
        $entry.All
        ''
    }
    $lines | Set-Content -Path $Export -Encoding ASCII
    Write-Host ''
    Write-Host "written to $Export" -ForegroundColor Green
}

Write-Host ''
