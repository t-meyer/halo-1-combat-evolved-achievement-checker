# Halo 1: Combat Evolved Achievement Checker

**Your achievement is stuck at 92% and the game will not tell you which mission
is missing. This finds it.**

For **Halo: Campaign Evolved** — the Halo 1 / Combat Evolved remake. Windows
only, nothing to install, and it never changes your save.

## Does this sound familiar?

- An achievement sits at 92% and will not unlock, and nothing tells you which
  mission is left
- You finished the campaign, but the achievement did not pop
- `Mix Master` is stuck and replaying missions at random changes nothing
- You want to know which missions you still owe on Heroic, on Legendary, on
  Remix, or without dying
- You are not sure which skulls and terminals you already have

Then this is for you.

## The problem

Some achievements need all thirteen campaign missions. `Mix Master`, for
example: finish the whole Remix campaign without dying once.

You play, you die a few times, you replay. At some point the game says **92%**.
So twelve missions are done and one is not — but the game never says *which*
one. Neither does the Xbox achievement list, and that is not an oversight you
can work around: Xbox stores this achievement as a single number for the whole
campaign, so there is genuinely nothing more for it to show.

The usual advice is to replay all thirteen missions until the number moves.
That is an entire evening, or several.

## What this does

Every time you finish a mission, the game writes that down in a file on your PC.
That file knows exactly which missions you have done, on which difficulty, and
which ones you have not. This tool reads it and prints the list:

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

`x` means done, `.` means not done. The last line names the mission you still
owe. That is the whole point.

**It only ever reads.** Your save is never changed, moved or deleted. Your Xbox
account is not touched, and nothing is sent anywhere.

## What you need

- A Windows PC **on which you have played the game**. If you only played on an
  Xbox console, your save lives in Microsoft's cloud and there is no file on
  your PC to read — this cannot help you then.
- Nothing else. PowerShell is already part of every Windows 10 and 11.
- No installation, no account, no admin rights, no API key.

## Step by step

1. Click the green **Code** button at the top of this page, then
   **Download ZIP**.
2. Right-click the downloaded file, choose **Extract All**, and confirm.
3. Open the folder you just extracted. Hold **Shift**, right-click on an empty
   spot inside the folder, and choose **Open PowerShell window here** (on
   Windows 11 it may read **Open in Terminal**).
4. Type this and press Enter:

   ```powershell
   .\halo-1-combat-evolved-achievement-checker.ps1
   ```

   You do not have to type all of it: type `.\halo` and press the **Tab** key,
   Windows completes the rest.

5. If Windows refuses to run it, the file is marked as "downloaded from the
   internet". Run this once, then repeat step 4:

   ```powershell
   Unblock-File .\halo-1-combat-evolved-achievement-checker.ps1
   ```

6. Read the table. Done.

> **Run the file — do not copy the script text into the PowerShell window.**
> Pasted code does not know where it lives, so it stops immediately with
> *"Cannot bind argument to parameter 'Path' because it is an empty string"* /
> *"Das Argument kann nicht an den Parameter 'Path' gebunden werden"*.

## Reading the result

- Each row is one mission, each column one difficulty. `Rmx-DL` is Remix
  deathless — the one behind `Mix Master`.
- The `completed` row counts the `x` per column.
- When a column is missing four missions or fewer, you get a `still missing:`
  line underneath that names them. That is your to-do list.
- `Skulls collected` and `Terminals found` are listed below the table.
- The columns are read out of the save, not built into the tool. If a game
  patch ever adds a completion set, it gets its own column and is named under
  the table.
- **A LASO column may or may not be possible — that is still open.** No save
  from a finished LASO run has been examined yet. If the game records one, it
  appears here by itself; if it only records `Legendary` and `Remix.Deathless`,
  it cannot be told apart from two ordinary runs. See
  [`docs/SAVE-FORMAT.md`](docs/SAVE-FORMAT.md) for how to settle it.

If several people play on the same PC, every Xbox account gets its own table,
with the gamertag in the heading.

## Something went wrong

| What you see | What it means |
| --- | --- |
| `No Halo: Campaign Evolved save found` | The game was never played on this PC, or only on a console. There is no local file to read. |
| `Cannot bind argument to parameter 'Path'` | You pasted the script text into the window instead of running the file. See the box above. |
| Windows refuses to run the script | Run `Unblock-File` as shown in step 5. |
| `Unrecognised tags` at the end | The game was patched and writes something new. The table is still correct; an issue with that list is welcome. |

Nothing here can damage your save — the tool contains no code that writes to it.

## Sharing your result

The heading line and the JSON export contain your XUID and your gamertag. The
mission table itself does not. Copy just the table when you post it somewhere.

## Auf Deutsch

Kurzfassung für deutschsprachige Spieler: Wenn ein Achievement bei 92 % hängt
und das Spiel nicht verrät, **welche Mission** noch fehlt, liest dieses Werkzeug
deinen Spielstand aus und nennt sie beim Namen — auch für Heroisch, Legendär,
Remix und "ohne zu sterben", dazu Schädel und Terminals.

Du brauchst einen Windows-PC, auf dem du gespielt hast. Lade oben über den
grünen **Code**-Knopf das ZIP herunter, entpacke es, öffne den Ordner, halte
**Umschalt** gedrückt, rechtsklicke auf eine freie Stelle, wähle
**PowerShell-Fenster hier öffnen** und tippe `.\halo` gefolgt von der
**Tab**-Taste. Falls Windows sich weigert, einmal `Unblock-File` ausführen wie
in Schritt 5 oben.

Dein Spielstand wird ausschließlich gelesen, niemals verändert. Wichtig: die
Datei **ausführen**, nicht den Skripttext ins Fenster hineinkopieren — sonst
kommt die Meldung *"Das Argument kann nicht an den Parameter 'Path' gebunden
werden"*.

## More options

```powershell
# everything the save knows
.\halo-1-combat-evolved-achievement-checker.ps1

# just the mission matrix, plus a JSON dump
.\halo-1-combat-evolved-achievement-checker.ps1 -Section Missions -Json progress.json

# one specific Xbox account on a shared PC
.\halo-1-combat-evolved-achievement-checker.ps1 -Account 2533274833271139

# a save folder copied off another PC, or a single save blob
.\halo-1-combat-evolved-achievement-checker.ps1 -SavePath D:\backup\wgs

# every gameplay tag in the file, unparsed
.\halo-1-combat-evolved-achievement-checker.ps1 -Raw
```

`Get-Help .\halo-1-combat-evolved-achievement-checker.ps1 -Full` lists all
parameters.

### Achievements from Xbox Live

`Get-HaloAchievements.ps1` lists all 58 achievements with their unlock state and
progress. This one is optional and needs a free API key from
[xbl.io](https://xbl.io) (sign in with your Microsoft account, copy the key from
your profile).

```powershell
.\Get-HaloAchievements.ps1 -Missing
.\Get-HaloAchievements.ps1 -Gamertag "AFriend"
```

The key can also live in the `HALO_XBL_KEY` environment variable so you are not
asked for it every run.

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
- Work out what the two ~1 MB `CoreSave_*` containers hold — measured: no
  gameplay tags whatsoever, so whatever is in them is in another format

## Contributing

Bug reports and PRs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The
most useful thing anyone can send is a confirmation of which bonus mission is
`e10`, `e20` and `e30`.

## Licence

MIT — see [LICENSE](LICENSE).

Not affiliated with, endorsed by, or connected to Microsoft, Xbox Game Studios
or 343 Industries. Halo is a trademark of Microsoft.
