# Halo Achievement Checker

Read your **Halo: Campaign Evolved** campaign progress straight out of the save
file, and see exactly which missions each achievement is still waiting on.

The game only ever shows you a percentage. If `Mix Master` sits at 92%, you know
twelve of the thirteen Remix missions are done deathless — but not which one is
left, and replaying all thirteen to find out is not a great evening. This tool
reads the save and tells you.

```
#   Mission                          Easy    Normal  Heroic  Legend  Remix   Rmx-DL
----------------------------------------------------------------------------------
1   The Pillar of Autumn             x       x       x       x       x       x
2   Halo                             x       x       x       x       x       x
3   The Truth and Reconciliation     x       x       x       x       x       .
...
----------------------------------------------------------------------------------
    completed                        13/13   13/13   11/13   11/13   13/13   12/13
  Remix.Deathless  still missing: The Truth and Reconciliation [a50]
```

Read-only. Nothing is ever written to your save.

_Previously published as `blamscan` — old links redirect here._

## Quick start

For anyone who just wants to know which mission is missing:

1. Get the files — on <https://github.com/t-meyer/halo-achievement-checker> click
   **Code → Download ZIP**, or

   ```powershell
   git clone https://github.com/t-meyer/halo-achievement-checker.git
   ```

2. Open PowerShell in that folder and run

   ```powershell
   .\halo-achievement-checker.ps1
   ```

3. Read the bottom of the table. The `completed` row is your progress per
   difficulty, and every column short of 13/13 by four missions or fewer gets a
   `still missing:` line naming the missions by name.

If Windows refuses to run a script you downloaded:

```powershell
Unblock-File .\halo-achievement-checker.ps1
powershell -ExecutionPolicy Bypass -File .\halo-achievement-checker.ps1
```

No installation, no dependencies, nothing is written anywhere.

## Requirements

Windows with PowerShell 5.1 or later — that is what ships with Windows 10 and 11,
nothing to install. The game must have been played on that PC; an Xbox console
keeps its save in the cloud, where there is no local file to read.

## Usage

```powershell
# everything the save knows
.\halo-achievement-checker.ps1

# just the mission matrix, plus a JSON dump
.\halo-achievement-checker.ps1 -Section Missions -Json progress.json

# one specific Xbox account on a shared PC
.\halo-achievement-checker.ps1 -Account 2533274833271139

# a save folder copied off another PC, or a single save blob
.\halo-achievement-checker.ps1 -SavePath D:\backup\wgs

# every gameplay tag in the file, unparsed
.\halo-achievement-checker.ps1 -Raw
```

`Get-Help .\halo-achievement-checker.ps1 -Full` lists all parameters.

> **Before you paste output into a forum:** the header line and the JSON export
> contain your XUID and gamertag. The mission table itself does not — copy just
> that part, or strip the identifiers first.

### Achievements from Xbox Live

`Get-HaloAchievements.ps1` lists all 58 achievements with their unlock state and
progress. It needs a free API key from [xbl.io](https://xbl.io) (sign in with
your Microsoft account, copy the key from your profile).

```powershell
.\Get-HaloAchievements.ps1 -Missing
.\Get-HaloAchievements.ps1 -Gamertag "AFriend"
```

The key can also live in the `HALO_XBL_KEY` environment variable so you are
not asked for it every run.

A friend's data is readable as long as their Xbox privacy settings let friends
see game history, which is the default. Names come back in the account's console
language.

The two scripts answer different halves of the same question: Xbox Live knows
*which achievements* are missing, the save knows *which missions* are missing.

## How it works

Progress is not in the `Meteorite` folder where you would look for it. It lives
in the Xbox Connected Storage container under a package name that gives no hint
it belongs to Halo, as a set of Unreal gameplay tags:

```
Blam.Progress.Mission.Completion.Remix.Deathless.a50
Blam.Skull.IWHBYD
Blam.Terminal.terminal_c20
```

A tag exists only once you have earned it, so what is missing from the file is
the answer. [`docs/SAVE-FORMAT.md`](docs/SAVE-FORMAT.md) has the full write-up:
container layout, tag taxonomy, mission ids, and why the achievement API cannot
answer this on its own.

## Known gaps

The three bonus missions are Boarding Action, The Most Dangerous Game and Heavy
Burden, but which one is `e10`, `e20` and `e30` is not yet confirmed — the
insertion point names suggest `e30` is Boarding Action. If you can pin these
down, a PR to `data/missions.json` is very welcome.

Skull and terminal lists come from a single save, so the totals may not be the
complete set the game defines.

## Roadmap

- Map every achievement to the concrete missions, skulls, terminals and skull
  combinations it needs, so the tool can print a to-do list instead of a matrix
- Confirm the bonus mission ids
- Decode `TrainingBlobBitvectorLow` / `High`
- Read the `CoreSave_*` containers for per-checkpoint detail

## Contributing

Bug reports and PRs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The
most useful thing anyone can send is a confirmation of which bonus mission is
`e10`, `e20` and `e30`.

## Licence

MIT — see [LICENSE](LICENSE).

Not affiliated with, endorsed by, or connected to Microsoft, Xbox Game Studios
or 343 Industries. Halo is a trademark of Microsoft.
