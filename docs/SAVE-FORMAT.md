# Halo: Campaign Evolved — save format notes

Everything here was worked out by reading a real save. No official documentation
was available. Corrections welcome.

## Where the data lives

The game is an Unreal Engine 5 title built on the GDK (its config folder is
`Saved/Config/WinGDK`). That split matters, because progress is **not** kept
where you would expect it.

| Path | Contains |
| --- | --- |
| `%LOCALAPPDATA%\Meteorite\Saved\Config\` | graphics, audio, input settings |
| `%LOCALAPPDATA%\Meteorite\Saved\BlamData\preferences.dat` | settings, control bindings, UI state — **no campaign progress** |
| `%LOCALAPPDATA%\Meteorite\Saved\BlamData\autosave\*.film` | gameplay recordings, up to ~200 MB each |
| `%LOCALAPPDATA%\Meteorite\Saved\AuthHaloStorage.json` | XUID ↔ gamertag of the signed-in account |
| `%LOCALAPPDATA%\Packages\Microsoft.198377053870B_8wekyb3d8bbwe\SystemAppData\wgs\` | **campaign progress** (Xbox Connected Storage) |

`Meteorite` is the engine-side project name of the game; the version string in
the save reads `++Meteorite+Rel-i343-Meteorite-2607-CU4`.

There is no `SaveGames` folder. Anyone looking for a `.sav` in the Meteorite
tree will come up empty.

### Finding the package reliably

The package family name `Microsoft.198377053870B_8wekyb3d8bbwe` contains no hint
that it is Halo. Two ways to identify it:

- `containers.index` inside it holds the UTF-16 string
  `Microsoft.198377053870B_8wekyb3d8bbwe!AppHaloCampaignEvolvedShipping`
- its SCID is `00000000-0000-0000-0000-00007c27bae7`, which also shows up in the
  Xbox Live stats API for title `2082978535`

### Connected Storage layout

```
wgs/
├── containers.index                      UTF-16, lists container names
└── <XUID-as-hex>_<SCID-without-dashes>/
    ├── container.<n>                     small, names the blob below
    └── <GUID>                            the actual save blob
```

The folder prefix is the XUID in hex — `00090000028E3963` is decimal
`2533274833271139`. On a PC where several Xbox accounts have played, each gets
its own folder, so tools must report per account rather than picking the
largest file.

`containers.index` names three containers:

| Container | Size | Contents |
| --- | --- | --- |
| `CoreSave_0` | ~1 MB | checkpoint state - **contains no `Blam.` tags at all** |
| `CoreSave_2` | ~1 MB | checkpoint state - **contains no `Blam.` tags at all** |
| `Progress` | ~19 KB | **persistent progression — this is the interesting one** |

## The Progress blob

A plain Unreal `GVAS` save:

```
47 56 41 53   "GVAS"
03 00 00 00   save game version
...
"++Meteorite+Rel-i343-Meteorite-2607-CU4"
```

Root class: `/Script/BlamEngine.BlamProgressLocalPlayerSaveGame`, containing

- `GameProgression` → `BlamGameProgression`
  - `Flags` → `BlamGameProgressionFlags` (`bHasPreviouslyCompletedCalibration`, …)
- `GameProfile` → `BlamGameProfile`
  - `PlayerTraining` with `TrainingBlobBitvectorLow` / `High` (int bitfields)
- `GameplayTags` → `GameplayTagContainer`

Almost everything worth reading sits in that tag container.

## Gameplay tags

**A tag is present only when the player has earned it.** That is what makes the
file useful: absence is the signal. In a save with every mission finished on
Normal, only 11 of the 13 `Heroic` tags existed.

| Tag pattern | Meaning |
| --- | --- |
| `Blam.Progress.Mission.Completion.Easy.<id>` | mission finished on Easy |
| `Blam.Progress.Mission.Completion.Normal.<id>` | … on Normal |
| `Blam.Progress.Mission.Completion.Heroic.<id>` | … on Heroic |
| `Blam.Progress.Mission.Completion.Legendary.<id>` | … on Legendary |
| `Blam.Progress.Mission.Completion.Remix.<id>` | Remix run finished |
| `Blam.Progress.Mission.Completion.Remix.Deathless.<id>` | Remix run finished without dying |
| `Blam.Progress.Mission.Completion.LASO.<id>` | finished on the LASO playlist - Legendary, all skulls on |
| `Blam.Progress.Mission.Completion.unlock_<id>` | mission unlocked in the menu |
| `Blam.Skull.<SkullName>` | skull collected |
| `Blam.Terminal.terminal_<id>` | terminal found |
| `Blam.Progress.Mission.InsertionPoints.ins_<id>_<name>` | checkpoint / insertion point reached |

### Seven completion sets, LASO included

```
Easy  Heroic  Legendary  Normal  Remix  Remix.Deathless  LASO
```

`LASO` is confirmed: finishing a mission on the LASO playlist writes
`Blam.Progress.Mission.Completion.LASO.<mission id>` into `Progress`, one tag
per mission, exactly like the other six. Two finished LASO missions took a save
from 185 tags to 187 and produced a `2/13` column.

It took a while to establish, and the wrong turns are worth recording:

- A save from a player who had never run LASO has no `LASO` set, which proves
  nothing either way - a tag exists only once it is earned. Absence is only
  evidence when the thing has been attempted.
- `IsLASO` turns up in the checkpoint containers and is **not** the answer. It
  is a field name in the game-variant schema described below, present whether
  or not the flag is ever set.

The reader does not hardcode this list. It splits everything after
`Blam.Progress.Mission.Completion.` at the last dot: the trailing segment is the
mission id, whatever precedes it is the set name. That is why `LASO` appeared as
its own column the first time a save contained it, with no code change - and why
an eighth set would do the same.

### The checkpoint containers carry a game-variant schema

Scanning whole strings rather than `Blam.` tags turns up **`IsLASO`** in the
save. It is not a gameplay tag, which is why every pass that looked only at
`Blam.` names missed it.

It sits in both checkpoint containers at nearly the same offset - 0xd75 in one,
0xd7f in the other - and in neither case in the 19 KB `Progress` blob. Around it
is a run of names that reads as the schema of a game variant:

```
<skull names...> EyePatch Mythic Thunderstorm ThatsJustWrong Temperamental
Boom GruntBirthdayPty Funeral IWHBYD ... Iron Fog EnduranceSpec StowAndGrow
Adapta... Reload Armistice
ActiveSkulls
bFriendlyFireEnabledBool
IsLASO
None                      <- GVAS end-of-list marker
VariantStorage
EncounterRemixR...omSeedUInt32
PerPlayerTrait  Vitality  DamageResistPercentageSetting  ShieldRechargeRate
Weapon  Melee  Modifier  InfiniteAmmo  BottomlessClip
```

Two things follow, and both are easy to get wrong:

- **`IsLASO` is a field name, not a value.** The names carry type suffixes
  (`...Bool`, `...UInt32`, `...Setting`) and sit together ahead of `None`, which
  is what a schema listing looks like. The same block appears in a container
  written before any LASO run. Its presence says the game has the field; it says
  nothing about whether the flag is set. The value lives elsewhere in the blob,
  so the byte after the name is not it.
- **`ActiveSkulls` exists**, so which skulls are on *is* recorded - for the
  session in progress, in the checkpoint container. That is the half of the LASO
  condition `Progress` lacks, but it is current state, not history.

Nothing here is per-mission and nothing here is permanent: these containers are
rewritten as you play. A LASO column would need a durable per-mission record,
and the only place that could live is `Progress`.

### Confirming a set yourself

`Debug-SaveTags.ps1` exists for this. Export, play, export again against the
first file:

```powershell
.\Debug-SaveTags.ps1 -Strings -Export before.txt
# ... finish one mission in the mode you are testing ...
.\Debug-SaveTags.ps1 -Strings -Export after.txt -Baseline before.txt
```

`-Strings` collects every printable run rather than only `Blam.` names, reading
each container both as single-byte and as UTF-16 since GVAS mixes the two.
`-Inspect <regex>` dumps the bytes around a name as hex and text, which is how
the variant schema above was read.

### Tag inventory

One save carried 185 distinct tags, and they account for the file completely:

| Family | Count |
| --- | --- |
| `Blam.Progress.Mission.Completion` | 85 |
| `Blam.Skull` | 45 |
| `Blam.Progress.Mission.InsertionPoints` | 42 |
| `Blam.Terminal` | 13 |

`Debug-SaveTags.ps1` in this repo prints that breakdown for any save.

### Mission ids

`a15 a30 a50 b30 b40 c10 c20 c40 d20 d40 e10 e20 e30`

The ten classic Halo: Combat Evolved level codes carry over, except that the
first mission is `a15` rather than the original `a10`. Terminals still use
`terminal_a10`, so the rename was not applied everywhere. `e10`, `e20` and `e30`
are the three bonus missions added for this release.

`c45` shows up in `unlock_c45` and in insertion points but never under a
difficulty completion tag — most likely a sub-section of another mission.

## Why this beats the achievement API

The `Mix Master` achievement (finish a whole Remix campaign without dying) is
modelled on Xbox Live as a **single summed requirement**, not thirteen:

```json
{ "id": "00000000-0000-0000-0000-000000000000",
  "current": "92", "target": "100", "operationType": "Sum" }
```

92 of 100 means 12 of 13 missions and nothing more. The save file is the only
place that says which one is outstanding.

## Reading it

Full GVAS parsing is not needed. The tags are stored as plain ASCII inside the
blob, so a regex over the raw bytes gets them all and keeps working across game
patches:

```
Blam\.[A-Za-z0-9_.]+
```

That is exactly what `halo-1-combat-evolved-achievement-checker.ps1` does.
