# Halo 1: Combat Evolved Achievement Checker

**Your achievement is stuck at 92% and the game will not tell you which mission
is missing. This finds it — for `Mix Master`, for `MYTHIC`, for every difficulty
including LASO.**

For **Halo: Campaign Evolved** — the Halo 1 / Combat Evolved remake. Windows
only, nothing to install, and it never changes your save.

## Does this sound familiar?

- An achievement sits at 92% and will not unlock, and nothing tells you which
  mission is left
- You finished the campaign, but the achievement did not pop
- `Mix Master` is stuck and replaying missions at random changes nothing
- `MYTHIC` will not pop and you have lost track of which missions you already
  cleared on LASO
- You want to know which missions you still owe on Heroic, on Legendary, on
  Remix, or without dying
- You are not sure which skulls and terminals you already have

Then this is for you.

## The problem

Two achievements ask for all thirteen campaign missions, and both go wrong in
exactly the same way:

- **`Mix Master`** — finish the whole Remix campaign without dying once.
- **`MYTHIC`** — finish every mission on **LASO**: Legendary difficulty with
  every skull switched on.

You play, you die somewhere, you replay that mission. At some point the game
says **92%**. So twelve missions counted and one did not — but the game never
says *which*. Neither does the Xbox achievement list, and that is not an
oversight you can work around: Xbox stores each of these as a single number for
the whole campaign, so there is genuinely nothing more for it to show.

The usual advice is to replay all thirteen missions until the number moves. For
`Mix Master` that is an evening, or several. For `MYTHIC` it is considerably
worse — nobody replays thirteen LASO missions on the off chance.

## What this does

Every time you finish a mission, the game writes that down in a file on your PC.
That file knows exactly which missions you have done, on which difficulty, and
which ones you have not. This tool reads it and prints the list:

```
#   Mission                          Easy    Normal  Heroic  Legend  Remix   Rmx-DL  LASO
------------------------------------------------------------------------------------------
1   The Pillar of Autumn             x       x       x       x       x       x       x
2   Halo                             x       x       x       x       x       x       x
3   The Truth and Reconciliation     x       x       x       x       x       .       .
...
------------------------------------------------------------------------------------------
    completed                        13/13   13/13   11/13   11/13   13/13   12/13   2/13
  Remix.Deathless  still missing: The Truth and Reconciliation [a50]
```

`x` means done, `.` means not done. The last line names the mission you still
owe. That is the whole point.

Here it is against a real save, with the account line blacked out:

![The tool run against a real save: a mission table with Easy, Normal, Heroic,
Legendary, Remix, Remix deathless and LASO columns, a completed row, the
missions still missing per column, 45 skulls and 13 terminals](docs/example-output.png)

**It only ever reads.** Your save is never changed, moved or deleted. Your Xbox
account is not touched, and nothing is sent anywhere.

## What you need

- A Windows PC **on which you have played the game**. If you only played on an
  Xbox console, your save lives in Microsoft's cloud and there is no file on
  your PC to read — this cannot help you then.
- Nothing else. PowerShell is already part of every Windows 10 and 11, so
  there is nothing to download besides this.
- No installation, no account, no administrator rights, no API key, and no
  experience with PowerShell.

## Which file do I run?

The download contains three files ending in `.ps1`. You only need the first.

| File | What it is |
| --- | --- |
| **`halo-1-combat-evolved-achievement-checker.ps1`** | **This is the one.** Reads your save and prints the table. |
| `Get-HaloAchievements.ps1` | Optional extra, lists all 58 achievements from Xbox Live. It needs a free key, so it asks for one. If your window says `OpenXBL API key:`, you started this file by mistake — press **Ctrl+C** and start the right one. |
| `Debug-SaveTags.ps1` | For people taking the save format apart. You do not need it. |

## Step by step

No experience needed. Nothing gets installed, nothing is changed on your PC.

1. Click the green **Code** button at the top of this page, then
   **Download ZIP**.

2. Find the downloaded file, right-click it, choose **Extract All**, and
   confirm. You now have a folder with the files in it.

3. Open that folder. Click into the **address bar** at the top of the window —
   the strip showing the folder path — type `powershell` over it and press
   **Enter**.

   A dark window opens, already pointing at the right folder. That is all the
   address-bar trick does; it is the most reliable way, because the right-click
   menu does not offer PowerShell on every Windows.

4. Type `.\halo`, press the **Tab** key — Windows completes the long file name
   for you — then press **Enter**.

   The full command is:

   ```powershell
   .\halo-1-combat-evolved-achievement-checker.ps1
   ```

5. Read the table. Done. If instead you got a red error message, the next
   section has it.

> **Two things that trip people up.** Do not run this as Administrator — it is
> not needed, and it starts you in the wrong folder. And run the *file*; do not
> copy the script text into the window. Pasted code does not know where it
> lives and stops with *"Cannot bind argument to parameter 'Path' because it is
> an empty string"* / *"Das Argument kann nicht an den Parameter 'Path'
> gebunden werden"*.

## Reading the result

- Each row is one mission, each column one difficulty. `Rmx-DL` is Remix
  deathless, the one behind `Mix Master`; `LASO` is Legendary with all skulls
  on, the one behind `MYTHIC`.
- The `completed` row counts the `x` per column.
- When a column is missing four missions or fewer, you get a `still missing:`
  line underneath that names them. That is your to-do list.
- `Skulls collected` and `Terminals found` are listed below the table.
- The columns are read out of the save, not built into the tool. If a game
  patch ever adds a completion set, it gets its own column and is named under
  the table.
- The `LASO` column only appears once you have finished at least one mission on
  the LASO playlist — until then the save has nothing to show. Same for every
  other column: a set the game never wrote does not exist in the file.

If several people play on the same PC, every Xbox account gets its own table,
with the gamertag in the heading.

## Something went wrong

| What you see | What to do |
| --- | --- |
| **"running scripts is disabled on this system"** / *"Die Ausfuehrung von Skripts ist auf diesem System deaktiviert"* | Windows blocks scripts by default. This runs it once without changing that setting: `powershell -ExecutionPolicy Bypass -File .\halo-1-combat-evolved-achievement-checker.ps1` |
| **"...is not digitally signed"** or a warning that the file came from the internet | Run `Unblock-File .\halo-1-combat-evolved-achievement-checker.ps1` once, then try again. It only removes the "downloaded" mark. |
| **`OpenXBL API key:`** and it waits for input | You started the wrong file. Press **Ctrl+C**, then run the one from the table above. |
| **`No Halo: Campaign Evolved save found`** | The game was never played on this PC, or only on an Xbox console. In that case the save is in Microsoft's cloud and there is no file here to read. |
| **`Cannot bind argument to parameter 'Path'`** | You pasted the script text into the window instead of running the file. See the box above. |
| **`The term '.\halo-1-...' is not recognized`** | The window is not in the right folder. Close it and redo step 3 from inside the extracted folder. |
| **`Unrecognised tags`** at the end | Harmless. The game was patched and writes something new; the table above it is still correct. An issue with that list is welcome. |

Nothing here can damage your save — the tool contains no code that writes to
it. If you are stuck, open an issue and paste what the window says.

## Sharing your result

The heading line and the JSON export contain your XUID and your gamertag. The
mission table itself does not. Copy just the table when you post it somewhere.

## Auf Deutsch

Kurzfassung für deutschsprachige Spieler: Wenn ein Achievement bei 92 % hängt
und das Spiel nicht verrät, **welche Mission** noch fehlt, liest dieses Werkzeug
deinen Spielstand aus und nennt sie beim Namen — auch für Heroisch, Legendär,
Remix, "ohne zu sterben" und LASO (Legendär mit allen Schädeln, das Achievement
`MYTHIC`), dazu Schädel und Terminals.

Du brauchst nur einen Windows-PC, auf dem du das Spiel gespielt hast. Es wird
nichts installiert und nichts an deinem Rechner verändert.

1. Oben über den grünen **Code**-Knopf das ZIP herunterladen.
2. Rechtsklick auf die Datei, **Alle extrahieren**, bestätigen.
3. Den entpackten Ordner öffnen. Oben in die **Adressleiste** klicken, dort
   `powershell` eintippen und **Enter** drücken — es öffnet sich ein dunkles
   Fenster, das bereits im richtigen Ordner steht.
4. `.\halo` tippen, **Tab** drücken (Windows vervollständigt den langen
   Dateinamen), **Enter**.

Von den drei `.ps1`-Dateien brauchst du nur
`halo-1-combat-evolved-achievement-checker.ps1`. Fragt das Fenster nach einem
`OpenXBL API key`, hast du die falsche erwischt: **Strg+C** drücken und die
richtige starten.

Weigert sich Windows mit *"Die Ausführung von Skripts ist auf diesem System
deaktiviert"*, startet dieser Befehl das Skript einmalig, ohne eine Einstellung
zu ändern:

```powershell
powershell -ExecutionPolicy Bypass -File .\halo-1-combat-evolved-achievement-checker.ps1
```

Dein Spielstand wird ausschließlich gelesen, niemals verändert. Zwei Stolper-
steine: **nicht als Administrator** starten, und die Datei **ausführen** statt
den Skripttext ins Fenster zu kopieren — sonst kommt *"Das Argument kann nicht
an den Parameter 'Path' gebunden werden"*.

## More options

```powershell
# everything the save knows
.\halo-1-combat-evolved-achievement-checker.ps1

# just the mission matrix, plus a JSON dump
.\halo-1-combat-evolved-achievement-checker.ps1 -Section Missions -Json progress.json

# one specific Xbox account on a shared PC
.\halo-1-combat-evolved-achievement-checker.ps1 -Account 2533274812345678

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
