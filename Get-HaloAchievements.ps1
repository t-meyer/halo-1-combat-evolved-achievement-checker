<#
.SYNOPSIS
    List every Halo: Campaign Evolved achievement and its progress, from Xbox Live.

.DESCRIPTION
    Complements halo-1-combat-evolved-achievement-checker.ps1: that one reads what the local save knows,
    this one reads what Xbox Live knows. Together they cover all 58
    achievements of the game.

    Uses the OpenXBL gateway (https://xbl.io), which needs a free API key:
      1. Sign in at https://xbl.io with your Microsoft account
      2. Copy the API key from your profile page

    Works for your own account and - if their privacy settings allow friends
    to see game history, which is the default - for a friend's account too.

.PARAMETER ApiKey
    OpenXBL API key. Prompted for when omitted. Can also be set via the
    HALO_XBL_KEY environment variable.

.PARAMETER Gamertag
    Look up this gamertag instead of your own account.

.PARAMETER Xuid
    Look up this XUID directly (skips the gamertag search).

.PARAMETER Missing
    Only list achievements that are not unlocked yet.

.PARAMETER Json
    Write the full result to this path as JSON.

.EXAMPLE
    .\Get-HaloAchievements.ps1 -Missing

.EXAMPLE
    .\Get-HaloAchievements.ps1 -Gamertag "SomeFriend" -Json friend.json

.NOTES
    Achievement names and descriptions come back in the account's own
    console language, so a German account returns German strings.
#>

[CmdletBinding()]
param(
    [string]$ApiKey,
    [string]$Gamertag,
    [string]$Xuid,
    [switch]$Missing,
    [string]$Json
)

$ErrorActionPreference = 'Stop'

# Halo: Campaign Evolved on Xbox Live.
$TitleId = '2082978535'
$ApiBase = 'https://xbl.io/api/v2'

if (-not $ApiKey) { $ApiKey = $env:HALO_XBL_KEY }
if (-not $ApiKey) { $ApiKey = Read-Host 'OpenXBL API key' }

$headers = @{ 'x-authorization' = $ApiKey; 'Accept' = 'application/json' }

function Invoke-Xbl {
    param([string]$Path)
    try {
        $response = Invoke-RestMethod -Uri "$ApiBase/$Path" -Headers $headers -Method Get
    } catch {
        throw "Request to /$Path failed: $($_.Exception.Message)"
    }
    # OpenXBL wraps Xbox Live payloads in a "content" envelope.
    if ($response.PSObject.Properties.Name -contains 'content') { return $response.content }
    return $response
}

# --- resolve the account ----------------------------------------------------

if (-not $Xuid) {
    if ($Gamertag) {
        $found = Invoke-Xbl "search/$([uri]::EscapeDataString($Gamertag))"
        $Xuid  = ($found.people | Select-Object -First 1).xuid
        if (-not $Xuid) { throw "Gamertag '$Gamertag' not found." }
    } else {
        $me   = Invoke-Xbl 'account'
        $user = $me.profileUsers | Select-Object -First 1
        $Xuid = $user.id
        $Gamertag = ($user.settings | Where-Object id -eq 'Gamertag').value
    }
}

Write-Host ''
Write-Host ("Halo: Campaign Evolved - achievements for XUID {0}{1}" -f $Xuid, $(if ($Gamertag) { " ($Gamertag)" } else { '' })) -ForegroundColor Cyan

# --- fetch ------------------------------------------------------------------

$payload      = Invoke-Xbl "achievements/player/$Xuid/$TitleId"
$achievements = @($payload.achievements)
if ($achievements.Count -eq 0) { Write-Host 'No achievement data returned (private profile, or game never launched).' -ForegroundColor Yellow; return }

$rows = foreach ($a in $achievements) {

    $gamerscore = ($a.rewards | Where-Object type -eq 'Gamerscore' | Select-Object -First 1).value
    $requirements = @($a.progression.requirements)

    # Xbox drops the progression detail once an achievement is unlocked, so
    # percent is only meaningful while it is still in progress.
    $percent = $null
    if ($requirements.Count -eq 1 -and [double]$requirements[0].target -gt 0) {
        $percent = [math]::Round(100 * [double]$requirements[0].current / [double]$requirements[0].target, 1)
    }

    [pscustomobject]@{
        Name        = $a.name
        State       = $a.progressState
        Gamerscore  = [int]$gamerscore
        Percent     = $percent
        Unlocked    = if ($a.progressState -eq 'Achieved') { [datetime]$a.progression.timeUnlocked } else { $null }
        Description = $a.description
        Requirements = $requirements
    }
}

# --- report -----------------------------------------------------------------

$shown = if ($Missing) { $rows | Where-Object State -ne 'Achieved' } else { $rows }

$done  = @($rows | Where-Object State -eq 'Achieved')
$score = ($done | Measure-Object Gamerscore -Sum).Sum
$total = ($rows | Measure-Object Gamerscore -Sum).Sum

Write-Host ("{0} of {1} unlocked - {2}/{3} G" -f $done.Count, $rows.Count, $score, $total) -ForegroundColor Cyan
Write-Host ''

foreach ($row in ($shown | Sort-Object @{ e = { $_.State -eq 'Achieved' } }, Name)) {
    $mark  = switch ($row.State) { 'Achieved' { 'x' } 'InProgress' { '~' } default { '.' } }
    $color = switch ($row.State) { 'Achieved' { 'DarkGray' } 'InProgress' { 'Yellow' } default { 'Gray' } }
    $suffix = if ($null -ne $row.Percent -and $row.State -ne 'Achieved') { "  [$($row.Percent)%]" } else { '' }
    Write-Host ("  {0} {1,-34} {2,4}G{3}" -f $mark, $row.Name, $row.Gamerscore, $suffix) -ForegroundColor $color
    if ($row.State -ne 'Achieved' -and $row.Description) {
        Write-Host ("      {0}" -f $row.Description) -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host 'Tip: for the Remix deathless achievement the percentage alone will not tell you' -ForegroundColor DarkGray
Write-Host '     which mission is missing - run halo-1-combat-evolved-achievement-checker.ps1 on that PC for the per-mission list.' -ForegroundColor DarkGray
Write-Host ''

if ($Json) {
    $rows | ConvertTo-Json -Depth 6 | Set-Content -Path $Json -Encoding UTF8
    Write-Host "JSON written to $Json" -ForegroundColor Green
}
